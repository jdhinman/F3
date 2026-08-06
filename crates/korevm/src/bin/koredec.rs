//! koredec: decompile KoreVM chunks back to Lua source.
//!
//!   koredec <file>...                        source to stdout
//!   koredec --out-dir <dir> [--root <dir>]   write one .lua per input; --root keeps the
//!                                            input tree's layout instead of flattening
//!   koredec --summary <file>...              one line per file: note count, i.e. defects

use std::path::Path;
use std::process::ExitCode;

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let mut files = Vec::new();
    let mut out_dir: Option<String> = None;
    let mut root: Option<String> = None;
    let mut summary = false;

    while let Some(a) = args.next() {
        match a.as_str() {
            "--out-dir" => out_dir = args.next(),
            "--root" => root = args.next(),
            "--summary" => summary = true,
            "-h" | "--help" => {
                eprintln!("usage: koredec [--summary] [--out-dir <dir>] <file>...");
                return ExitCode::SUCCESS;
            }
            _ => files.push(a),
        }
    }
    if files.is_empty() {
        eprintln!("usage: koredec [--summary] [--out-dir <dir>] <file>...");
        return ExitCode::FAILURE;
    }

    let mut failed = 0usize;
    for path in &files {
        let data = match std::fs::read(path) {
            Ok(d) => d,
            Err(e) => {
                eprintln!("{path}: {e}");
                failed += 1;
                continue;
            }
        };
        let chunk = match korevm::parse(&data) {
            Ok(c) => c,
            Err(e) => {
                if summary {
                    println!("FAIL\t{path}\t{e}");
                } else {
                    eprintln!("{path}: {e}");
                }
                failed += 1;
                continue;
            }
        };
        let out = korevm::decompile::chunk(&chunk);
        let text = korevm::ast::render(&out.body);

        if summary {
            let lines = text.lines().count();
            println!("{}\t{path}\t{} notes\t{lines} lines", if out.notes.is_empty() { "clean" } else { "notes" }, out.notes.len());
        } else if let Some(dir) = &out_dir {
            let src = Path::new(path);
            let rel = root
                .as_ref()
                .and_then(|r| src.strip_prefix(r).ok())
                .map(|p| p.to_path_buf())
                .unwrap_or_else(|| Path::new(src.file_name().unwrap_or_default()).to_path_buf());
            let dest = Path::new(dir).join(rel);
            if let Some(parent) = dest.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            if let Err(e) = std::fs::write(&dest, &text) {
                eprintln!("{}: {e}", dest.display());
                failed += 1;
            }
        } else {
            print!("{text}");
        }
    }

    if failed > 0 {
        eprintln!("{failed} of {} file(s) failed", files.len());
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}
