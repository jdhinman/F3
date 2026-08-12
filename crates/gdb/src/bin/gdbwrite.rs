//! gdbwrite: prove the GDB writer round-trips, and add records.
//!
//!   gdbwrite --verify <file.gdb>            byte-identical round trip check
//!   gdbwrite --verify --bank <bnk> [--entry p]
//!   gdbwrite --verify-all --bank <bnk>      every .gdb in the bank
//!   gdbwrite --bank <bnk> --clone <src> --name <new> [--set Field=value]...
//!   gdbwrite <file.gdb> --edit <record> --set Field=value --out <path>
//!
//! The verify mode is the whole justification for the writer: if parse-then-write does not
//! reproduce the input exactly, nothing built on top can be trusted. `--verify-all` is the
//! strong form of that claim, and the evidence for the label index in particular: the
//! index is rebuilt from scratch on every write, so 94 files reproducing byte for byte is
//! 94 independent tests of the probing scheme.
//!
//! `--set Field=value` takes a decimal number, or `"text"` in quotes for a string field,
//! which adds the label if it is not already there.

use std::process::ExitCode;

/// Object index for a record name, resolved the way the engine does it: FNV-1 of the name
/// through the name map to an object hash, then that hash to an object.
fn resolve(db: &gdb::Database, name: &str) -> Option<usize> {
    let want = gdb::fnv1(name);
    let Some(obj) = db.name_map.iter().find(|(n, _)| *n == want).map(|(_, o)| *o) else {
        eprintln!("{name}: not in the name map");
        return None;
    };
    match db.objects.iter().position(|o| o.hash == obj) {
        Some(i) => Some(i),
        None => {
            eprintln!("{name}: name maps to object {obj:08X}, which does not exist");
            None
        }
    }
}

/// Apply `Field=value` assignments. A quoted value is a string and becomes a label; a value
/// with a decimal point is an f32 bit pattern; anything else is a plain u32.
fn apply_sets(db: &mut gdb::Database, idx: usize, sets: &[String]) -> Result<(), ()> {
    for s in sets {
        let Some((field, raw)) = s.split_once('=') else {
            eprintln!("--set wants Field=value, got {s}");
            return Err(());
        };
        let value = if raw.len() >= 2 && raw.starts_with('"') && raw.ends_with('"') {
            let text = &raw[1..raw.len() - 1];
            match db.add_label(text) {
                Some(h) => { println!("  label {text:?} -> hash {h:08X}"); h }
                None => {
                    eprintln!("  {text:?}: FNV-1 collides with a different existing label; rename it");
                    return Err(());
                }
            }
        } else if raw.contains('.') {
            match raw.parse::<f32>() {
                Ok(v) => v.to_bits(),
                Err(_) => { eprintln!("  {raw}: not a number"); return Err(()); }
            }
        } else {
            match raw.parse::<u32>() {
                Ok(v) => v,
                Err(_) => { eprintln!("  {raw}: not a number, and not quoted"); return Err(()); }
            }
        };
        if !db.set_field(idx, field, value) {
            eprintln!("  {field}: this object's template has no such field");
            return Err(());
        }
        println!("  set {field} = {value}");
    }
    Ok(())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut path: Option<String> = None;
    let mut bank: Option<String> = None;
    let mut entry = String::from(r"globals\globals.gdb");
    let mut verify = false;
    let mut verify_all = false;
    let mut clone_of: Option<String> = None;
    let mut edit_of: Option<String> = None;
    let mut new_name: Option<String> = None;
    let mut out_path: Option<String> = None;
    let mut sets: Vec<String> = Vec::new();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--verify" => verify = true,
            "--verify-all" => verify_all = true,
            "--clone" => { i += 1; clone_of = args.get(i).cloned(); }
            "--edit" => { i += 1; edit_of = args.get(i).cloned(); }
            "--name" => { i += 1; new_name = args.get(i).cloned(); }
            "--set" => { i += 1; if let Some(s) = args.get(i) { sets.push(s.clone()) } }
            "--out" => { i += 1; out_path = args.get(i).cloned(); }
            "--bank" => { i += 1; bank = args.get(i).cloned(); }
            "--entry" => { i += 1; entry = args.get(i).cloned().unwrap_or(entry); }
            other => path = Some(other.to_string()),
        }
        i += 1;
    }

    // Every GDB in a bank, round-tripped. One failure is a failure overall.
    if verify_all {
        let Some(b) = bank.as_ref() else {
            eprintln!("--verify-all needs --bank");
            return ExitCode::FAILURE;
        };
        let index = std::fs::read(b).unwrap_or_default();
        let payload = std::fs::read(format!("{b}.dat")).unwrap_or_default();
        let Ok(parsed) = bnk::read_index(&index) else {
            eprintln!("{b}: not a bank");
            return ExitCode::FAILURE;
        };
        let (mut ok, mut fail, mut labels) = (0u32, 0u32, 0usize);
        for e in parsed.entries.iter().filter(|e| e.path.to_lowercase().ends_with(".gdb")) {
            let Some(data) = gdb::from_bank(&index, &payload, &e.path) else {
                eprintln!("FAIL {}: could not extract", e.path);
                fail += 1;
                continue;
            };
            match gdb::parse(&data) {
                Ok(db) => {
                    let out = db.to_bytes();
                    if out == data {
                        ok += 1;
                        labels += db.labels.len();
                    } else {
                        let at = out.iter().zip(data.iter()).position(|(a, b)| a != b);
                        eprintln!("FAIL {}: differs at {:?} (len {} vs {})",
                            e.path, at, out.len(), data.len());
                        fail += 1;
                    }
                }
                Err(err) => { eprintln!("FAIL {}: {err}", e.path); fail += 1; }
            }
        }
        println!("{ok} GDB files round-tripped byte for byte, {fail} failed, {labels} labels total");
        return if fail == 0 { ExitCode::SUCCESS } else { ExitCode::FAILURE };
    }

    let data = if let Some(b) = bank {
        let index = std::fs::read(&b).unwrap_or_default();
        let payload = std::fs::read(format!("{b}.dat")).unwrap_or_default();
        match gdb::from_bank(&index, &payload, &entry) {
            Some(d) => d,
            None => { eprintln!("{entry}: not found in {b}"); return ExitCode::FAILURE; }
        }
    } else if let Some(p) = path {
        match std::fs::read(&p) {
            Ok(d) => d,
            Err(e) => { eprintln!("{p}: {e}"); return ExitCode::FAILURE; }
        }
    } else {
        eprintln!("usage: gdbwrite --verify <file.gdb> | --verify --bank <x.bnk> [--entry <path>]");
        return ExitCode::FAILURE;
    };

    let mut db = match gdb::parse(&data) {
        Ok(d) => d,
        Err(e) => { eprintln!("parse: {e}"); return ExitCode::FAILURE; }
    };

    // Change fields on an EXISTING record, in place. This exists as the control for
    // "is the modified file even being loaded": a new record failing to resolve could mean
    // the file is not loaded OR that name resolution does not work for added objects, and
    // changing a value on a record the game already reads separates the two.
    if let Some(name) = edit_of.as_ref() {
        let Some(idx) = resolve(&db, name) else { return ExitCode::FAILURE };
        println!("editing {name} (object index {idx})");
        if apply_sets(&mut db, idx, &sets).is_err() {
            return ExitCode::FAILURE;
        }
        let bytes = db.to_bytes();
        let path = out_path.unwrap_or_else(|| "work/globals-modified.gdb".to_string());
        if let Err(e) = std::fs::write(&path, &bytes) {
            eprintln!("{path}: {e}");
            return ExitCode::FAILURE;
        }
        println!("wrote {} ({} bytes, was {})", path, bytes.len(), data.len());
        match gdb::parse(&bytes) {
            Ok(re) => println!("re-parsed OK: {} objects", re.objects.len()),
            Err(e) => { eprintln!("re-parse FAILED: {e}"); return ExitCode::FAILURE; }
        }
        return ExitCode::SUCCESS;
    }

    // Add a record by cloning an existing one and giving it a new name. Reusing the source
    // template is what makes this safe: template pointers index a block written back
    // verbatim, so nothing shifts.
    if let (Some(src_name), Some(name)) = (clone_of.as_ref(), new_name.as_ref()) {
        let Some(idx) = resolve(&db, src_name) else { return ExitCode::FAILURE };
        let src_obj = db.objects[idx].hash;
        // A fresh object hash that collides with nothing already present.
        let mut new_hash = gdb::fnv1(&format!("F3MOD::{name}"));
        while db.objects.iter().any(|o| o.hash == new_hash) {
            new_hash = new_hash.wrapping_add(1);
        }
        let Some(new_idx) = db.clone_object(idx, new_hash) else {
            eprintln!("clone failed");
            return ExitCode::FAILURE;
        };
        db.set_name(new_idx, name);
        println!("cloned {src_name} (object {src_obj:08X}) -> {name} (object {new_hash:08X})");

        if apply_sets(&mut db, new_idx, &sets).is_err() {
            return ExitCode::FAILURE;
        }

        let bytes = db.to_bytes();
        let path = out_path.unwrap_or_else(|| "work/globals-modified.gdb".to_string());
        if let Err(e) = std::fs::write(&path, &bytes) {
            eprintln!("{path}: {e}");
            return ExitCode::FAILURE;
        }
        println!("wrote {} ({} bytes, was {})", path, bytes.len(), data.len());
        // Re-parse what we wrote: a file that cannot be read back is not a file.
        match gdb::parse(&bytes) {
            Ok(re) => {
                let found = re.name_map.iter().any(|(n, _)| *n == gdb::fnv1(name));
                println!("re-parsed OK: {} objects, new name resolves: {}", re.objects.len(), found);
            }
            Err(e) => { eprintln!("re-parse FAILED: {e}"); return ExitCode::FAILURE; }
        }
        return ExitCode::SUCCESS;
    }

    if verify {
        let out = db.to_bytes();
        if out.len() != data.len() {
            eprintln!("FAIL length {} vs {} (delta {})", out.len(), data.len(),
                out.len() as i64 - data.len() as i64);
            return ExitCode::FAILURE;
        }
        if let Some(at) = out.iter().zip(data.iter()).position(|(a, b)| a != b) {
            eprintln!("FAIL first difference at 0x{at:X}: wrote {:02X}, expected {:02X}",
                out[at], data[at]);
            return ExitCode::FAILURE;
        }
        println!("round trip OK: {} bytes identical, {} objects, {} labels, {} name-map entries",
            out.len(), db.objects.len(), db.labels.len(), db.name_map.len());
    }
    ExitCode::SUCCESS
}
