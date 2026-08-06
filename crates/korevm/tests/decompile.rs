//! Decompiler tests. The corpus ones skip when `work/scripts` is absent; regenerate with
//!   .\tools\bnk-extract.ps1 -Bnk "<install>\data\gamescripts.bnk" -Out .\work\scripts

use std::path::{Path, PathBuf};

fn corpus() -> Option<Vec<PathBuf>> {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../work/scripts");
    if !root.exists() {
        return None;
    }
    let mut files = Vec::new();
    collect(&root, &mut files);
    files.sort();
    Some(files)
}

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

fn decompile(path: &Path) -> (String, usize) {
    let data = std::fs::read(path).unwrap();
    let chunk = korevm::parse(&data).unwrap();
    let out = korevm::decompile::chunk(&chunk);
    (korevm::ast::render(&out.body), out.notes.len())
}

/// The corpus is full of enum tables, so this shape is worth pinning exactly.
#[test]
fn enum_table_round_trips() {
    let Some(files) = corpus() else { return };
    let Some(f) = files.iter().find(|f| f.ends_with("agegroupenum.lua")) else { return };
    let (text, notes) = decompile(f);
    assert_eq!(notes, 0);
    assert!(text.contains("EAgeGroup = {"), "{text}");
    assert!(text.contains("EAGE_GROUP_BABY = 0"), "{text}");
    assert!(text.contains("EAGE_GROUP_NONE = 4"), "{text}");
}

/// ScriptActivation is the one file that ships as both source and bytecode, so it is the
/// only real ground truth. It must come back with nothing unrecovered.
#[test]
fn ground_truth_file_decompiles_clean() {
    let Some(files) = corpus() else { return };
    let Some(f) = files.iter().find(|f| f.ends_with("quests/scriptactivation.lua")) else {
        return;
    };
    let (text, notes) = decompile(f);
    assert_eq!(notes, 0, "expected a clean decompile of the ground-truth file");
    assert!(text.contains(r#"ScriptActivation[ScriptCode.QU000].name = "QU000_RoadToRule""#));
    assert!(text.contains("ScriptActivation[ScriptCode.QO030].AbleToRun = function()"));
}

/// Nothing in the corpus may panic, and the share of functions the structuring pass
/// cannot recover must stay small. The bound is a ratchet: tighten it when it improves,
/// and treat a failure as a regression rather than raising it.
#[test]
fn whole_corpus_decompiles_within_the_defect_budget() {
    let Some(files) = corpus() else { return };
    let mut with_notes = 0usize;
    let mut total_notes = 0usize;
    for f in &files {
        let (text, notes) = decompile(f);
        assert!(!text.is_empty(), "{} produced no output", f.display());
        if notes > 0 {
            with_notes += 1;
            total_notes += notes;
        }
    }
    assert!(
        with_notes <= 55,
        "{with_notes} of {} files carry notes ({total_notes} total)",
        files.len()
    );
}

#[test]
fn loops_and_conditionals_survive() {
    let Some(files) = corpus() else { return };
    let Some(f) = files.iter().find(|f| f.ends_with("ai/bargroupmind.lua")) else { return };
    let (text, _) = decompile(f);
    // This function nests an if, an inner if, a while and a break-free body. Getting the
    // while out of the enclosing condition chain was the hard part.
    assert!(text.contains("while i <= num_doors do"), "{text}");
    assert!(text.contains("local num_doors ="), "{text}");
}
