//! gdbwrite: prove the GDB writer round-trips, and add records.
//!
//!   gdbwrite --verify <file.gdb>            byte-identical round trip check
//!   gdbwrite --verify --bank <bnk> [--entry p]
//!
//! The verify mode is the whole justification for the writer: if parse-then-write does not
//! reproduce the input exactly, nothing built on top can be trusted.

use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut path: Option<String> = None;
    let mut bank: Option<String> = None;
    let mut entry = String::from(r"globals\globals.gdb");
    let mut verify = false;
    let mut clone_of: Option<String> = None;
    let mut new_name: Option<String> = None;
    let mut out_path: Option<String> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--verify" => verify = true,
            "--clone" => { i += 1; clone_of = args.get(i).cloned(); }
            "--name" => { i += 1; new_name = args.get(i).cloned(); }
            "--out" => { i += 1; out_path = args.get(i).cloned(); }
            "--bank" => { i += 1; bank = args.get(i).cloned(); }
            "--entry" => { i += 1; entry = args.get(i).cloned().unwrap_or(entry); }
            other => path = Some(other.to_string()),
        }
        i += 1;
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

    // Add a record by cloning an existing one and giving it a new name. Reusing the source
    // template is what makes this safe: template pointers index a block written back
    // verbatim, so nothing shifts.
    if let (Some(src_name), Some(name)) = (clone_of.as_ref(), new_name.as_ref()) {
        let src_hash = gdb::fnv1(src_name);
        let src_obj = db.name_map.iter().find(|(n, _)| *n == src_hash).map(|(_, o)| *o);
        let Some(src_obj) = src_obj else {
            eprintln!("{src_name}: not in the name map");
            return ExitCode::FAILURE;
        };
        let Some(idx) = db.objects.iter().position(|o| o.hash == src_obj) else {
            eprintln!("{src_name}: name maps to object {src_obj:08X}, which does not exist");
            return ExitCode::FAILURE;
        };
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
