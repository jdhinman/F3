//! bnkinfo: dump a bank index, including the fields whose meaning is unknown.
//!
//!   bnkinfo <file.bnk>

use std::process::ExitCode;

fn main() -> ExitCode {
    let Some(path) = std::env::args().nth(1) else {
        eprintln!("usage: bnkinfo <file.bnk>");
        return ExitCode::FAILURE;
    };
    let bytes = match std::fs::read(&path) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("{path}: {e}");
            return ExitCode::FAILURE;
        }
    };
    let bank = match bnk::read_index(&bytes) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("{path}: {e}");
            return ExitCode::FAILURE;
        }
    };
    println!(
        "{path}: version {}, compressed_flag {}, leading_word 0x{:08X}, {} entries",
        bank.version,
        bank.compressed_flag,
        bank.leading_word,
        bank.entries.len()
    );
    println!("{:<10} {:>10} {:>10} {:>10} {:>6}  {:<24} path", "hash", "offset", "size", "realSize", "chunks", "meta[7]");
    for e in &bank.entries {
        let meta: Vec<String> = e.meta.iter().map(|m| m.to_string()).collect();
        println!(
            "{:08X} {:>10} {:>10} {:>10} {:>6}  {:<24} {}",
            e.hash,
            e.offset,
            e.size,
            e.real_size,
            e.num_chunks,
            meta.join(","),
            e.path
        );
        // A mismatch here would mean the hash is not what the spec says it is.
        let expected = bnk::path_hash(&e.path);
        if expected != e.hash {
            println!("    ^ HASH MISMATCH: computed {expected:08X} from the path");
        }
    }
    ExitCode::SUCCESS
}
