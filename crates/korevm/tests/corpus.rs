//! Parses the extracted script corpus if it is present.
//!
//! The corpus is game data and is not committed, so this test skips when
//! `work/scripts` is absent. Regenerate it with:
//!   .\tools\bnk-extract.ps1 -Bnk "<install>\data\gamescripts.bnk" -Out .\work\scripts

use std::path::{Path, PathBuf};

fn collect(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for e in entries.flatten() {
        let p = e.path();
        if p.is_dir() {
            collect(&p, out);
        } else if p.extension().is_some_and(|x| x == "lua") {
            out.push(p);
        }
    }
}

#[test]
fn every_chunk_parses_to_the_last_byte() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../work/scripts");
    if !root.exists() {
        eprintln!("skipping: {} not present", root.display());
        return;
    }

    let mut files = Vec::new();
    collect(&root, &mut files);
    assert!(!files.is_empty(), "corpus directory exists but holds no .lua files");

    let mut failures = Vec::new();
    for f in &files {
        let data = std::fs::read(f).unwrap();
        match korevm::parse(&data) {
            // A chunk that parses to exactly its own length is the strongest cheap
            // signal the layout is right; a wrong layout leaves a tail or overruns.
            Ok(c) if c.size == data.len() => {}
            Ok(c) => failures.push(format!("{}: {} of {} bytes consumed", f.display(), c.size, data.len())),
            Err(e) => failures.push(format!("{}: {e}", f.display())),
        }
    }
    assert!(failures.is_empty(), "{} of {} failed:\n{}", failures.len(), files.len(), failures.join("\n"));
}

#[test]
fn no_instruction_falls_outside_the_opcode_table() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../work/scripts");
    if !root.exists() {
        return;
    }
    let mut files = Vec::new();
    collect(&root, &mut files);

    for f in &files {
        let data = std::fs::read(f).unwrap();
        let Ok(c) = korevm::parse(&data) else { continue };
        let mut protos = Vec::new();
        c.main.walk(&mut protos);
        for p in protos {
            for (pc, ins) in p.code.iter().enumerate() {
                assert!(
                    ins.info().is_some(),
                    "{}: pc {pc} has opcode {} outside 0..=86",
                    f.display(),
                    ins.opcode()
                );
            }
        }
    }
}
