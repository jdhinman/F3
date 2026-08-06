//! bnkpack: build a BNK bank from a directory tree.
//!
//!   bnkpack <src-dir> <out.bnk> [--meta a,b,c,d,e,f,g] [--leading N]
//!
//! Paths inside the bank are the tree-relative paths with backslashes, which is the form
//! the game's own banks use. Writes `<out.bnk>` and `<out.bnk>.dat`.
//!
//! The seven trailing words per path have unknown meaning. They default to zero; pass
//! `--meta` to copy the values from a real bank (see `bnkinfo`) if that turns out to
//! matter.

use std::path::{Path, PathBuf};
use std::process::ExitCode;

fn collect(root: &Path, dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    let mut items: Vec<_> = entries.flatten().map(|e| e.path()).collect();
    items.sort();
    for p in items {
        if p.is_dir() {
            collect(root, &p, out);
        } else {
            out.push(p);
        }
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut positional = Vec::new();
    let mut meta = [0u32; 7];
    let mut leading = 0u32;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--meta" => {
                i += 1;
                let Some(v) = args.get(i) else {
                    eprintln!("--meta needs seven comma-separated numbers");
                    return ExitCode::FAILURE;
                };
                let parts: Vec<&str> = v.split(',').collect();
                if parts.len() != 7 {
                    eprintln!("--meta needs exactly seven values, got {}", parts.len());
                    return ExitCode::FAILURE;
                }
                for (slot, p) in meta.iter_mut().zip(parts) {
                    match p.trim().parse() {
                        Ok(n) => *slot = n,
                        Err(e) => {
                            eprintln!("--meta: {p}: {e}");
                            return ExitCode::FAILURE;
                        }
                    }
                }
            }
            "--leading" => {
                i += 1;
                leading = args.get(i).and_then(|v| v.parse().ok()).unwrap_or(0);
            }
            other => positional.push(other.to_string()),
        }
        i += 1;
    }

    if positional.len() != 2 {
        eprintln!("usage: bnkpack <src-dir> <out.bnk> [--meta a,b,c,d,e,f,g] [--leading N]");
        return ExitCode::FAILURE;
    }
    let root = PathBuf::from(&positional[0]);
    let out_index = PathBuf::from(&positional[1]);
    let out_payload = PathBuf::from(format!("{}.dat", out_index.display()));

    if !root.is_dir() {
        eprintln!("{}: not a directory", root.display());
        return ExitCode::FAILURE;
    }

    let mut files = Vec::new();
    collect(&root, &root, &mut files);
    if files.is_empty() {
        eprintln!("{}: no files", root.display());
        return ExitCode::FAILURE;
    }

    let mut inputs = Vec::with_capacity(files.len());
    for f in &files {
        let rel = match f.strip_prefix(&root) {
            Ok(r) => r.to_string_lossy().replace('/', "\\"),
            Err(e) => {
                eprintln!("{}: {e}", f.display());
                return ExitCode::FAILURE;
            }
        };
        let data = match std::fs::read(f) {
            Ok(d) => d,
            Err(e) => {
                eprintln!("{}: {e}", f.display());
                return ExitCode::FAILURE;
            }
        };
        println!("  {:>9} B  {rel}", data.len());
        inputs.push(bnk::Input { path: rel, data, meta });
    }

    let (index, payload) = match bnk::write_bank(&inputs, leading) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("pack: {e}");
            return ExitCode::FAILURE;
        }
    };

    // Read our own output back before claiming success: a bank the reader cannot parse is
    // worse than no bank, because the failure would surface inside the game.
    match bnk::read_index(&index) {
        Ok(b) if b.entries.len() == inputs.len() => {}
        Ok(b) => {
            eprintln!("verify: wrote {} entries, read back {}", inputs.len(), b.entries.len());
            return ExitCode::FAILURE;
        }
        Err(e) => {
            eprintln!("verify: the bank we just wrote does not parse: {e}");
            return ExitCode::FAILURE;
        }
    }

    if let Err(e) = std::fs::write(&out_index, &index) {
        eprintln!("{}: {e}", out_index.display());
        return ExitCode::FAILURE;
    }
    if let Err(e) = std::fs::write(&out_payload, &payload) {
        eprintln!("{}: {e}", out_payload.display());
        return ExitCode::FAILURE;
    }
    println!(
        "wrote {} ({} B index) and {} ({} B payload), {} entries",
        out_index.display(),
        index.len(),
        out_payload.display(),
        payload.len(),
        inputs.len()
    );
    ExitCode::SUCCESS
}
