//! gdbdump: read a Fable III GDB object database.
//!
//!   gdbdump <file.gdb> [--find <text>] [--object <name>] [--stats]
//!   gdbdump --bank <levels.bnk> --entry globals\globals.gdb [...]
//!
//! With no filter it prints every object and field, which for globals.gdb is very large;
//! --find is almost always what you want.

use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut path: Option<String> = None;
    let mut bank: Option<String> = None;
    let mut entry = "globals\\globals.gdb".to_string();
    let mut find: Option<String> = None;
    let mut object: Option<String> = None;
    let mut stats = false;
    let mut names_only = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--bank" => { i += 1; bank = args.get(i).cloned(); }
            "--entry" => { i += 1; entry = args.get(i).cloned().unwrap_or(entry); }
            "--find" => { i += 1; find = args.get(i).cloned(); }
            "--object" => { i += 1; object = args.get(i).cloned(); }
            "--stats" => stats = true,
            "--names" => names_only = true,
            other => path = Some(other.to_string()),
        }
        i += 1;
    }

    let data = if let Some(b) = bank {
        let index = match std::fs::read(&b) {
            Ok(d) => d,
            Err(e) => { eprintln!("{b}: {e}"); return ExitCode::FAILURE; }
        };
        let payload = match std::fs::read(format!("{b}.dat")) {
            Ok(d) => d,
            Err(e) => { eprintln!("{b}.dat: {e}"); return ExitCode::FAILURE; }
        };
        match gdb::from_bank(&index, &payload, &entry) {
            Some(d) => d,
            None => { eprintln!("{entry}: not found in {b}, or stored compressed"); return ExitCode::FAILURE; }
        }
    } else if let Some(p) = path {
        match std::fs::read(&p) {
            Ok(d) => d,
            Err(e) => { eprintln!("{p}: {e}"); return ExitCode::FAILURE; }
        }
    } else {
        eprintln!("usage: gdbdump <file.gdb> | --bank <x.bnk> [--entry <path>] [--find <text>] [--object <name>] [--stats] [--names]");
        return ExitCode::FAILURE;
    };

    let db = match gdb::parse(&data) {
        Ok(d) => d,
        Err(e) => { eprintln!("parse: {e}"); return ExitCode::FAILURE; }
    };

    if stats {
        let named = db.objects.iter().filter(|o| db.name_of(o).is_some()).count();
        println!("{} objects ({} named), {} templates, {} labels",
            db.objects.len(), named, db.templates.len(), db.labels.len());
        return ExitCode::SUCCESS;
    }

    if std::env::var("GDB_PEEK").is_ok() {
        for o in db.objects.iter().take(3) {
            println!("OBJECT hash {:08X} template {:08X}", o.hash, o.template_pointer);
            if let Some(t) = db.template_of(o) {
                for (i, f) in t.fields.iter().enumerate().take(12) {
                    println!("    {:<36} {:<10} {}", db.field_name(o, i), gdb::type_name(f.datatype), db.field_value(o, i));
                }
            }
        }
        return ExitCode::SUCCESS;
    }
    let selected: Vec<&gdb::Object> = if let Some(n) = &object {
        db.objects.iter().filter(|o| db.name_of(o) == Some(n.as_str())).collect()
    } else if let Some(n) = &find {
        db.find(n)
    } else {
        db.objects.iter().collect()
    };

    if names_only {
        for o in &selected {
            if let Some(n) = db.name_of(o) {
                println!("{n}");
            }
        }
        println!("-- {} matched", selected.len());
        return ExitCode::SUCCESS;
    }

    for o in &selected {
        let name = db.name_of(o).unwrap_or("<unnamed>");
        let fields = db.template_of(o).map(|t| t.fields.len()).unwrap_or(0);
        println!("OBJECT {name}  hash {:08X}  template {:08X}  {fields} fields", o.hash, o.template_pointer);
        if let Some(t) = db.template_of(o) {
            for (i, f) in t.fields.iter().enumerate() {
                println!("    {:<40} {:<10} {}",
                    db.field_name(o, i), gdb::type_name(f.datatype), db.field_value(o, i));
            }
        }
    }
    println!("-- {} object(s)", selected.len());
    ExitCode::SUCCESS
}
