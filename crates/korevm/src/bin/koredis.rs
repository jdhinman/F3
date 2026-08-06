//! koredis: disassemble KoreVM chunks.
//!
//!   koredis <file>...            listing to stdout
//!   koredis --summary <file>...  one line per file, for sweeping the whole corpus
//!   koredis --opcodes <file>...  opcode-frequency histogram over the files given

use korevm::disasm::{self, Options};
use std::process::ExitCode;

/// Write to stdout, treating a closed pipe as a normal end rather than a panic, so
/// piping into `head` works.
fn write_out(s: &str) -> bool {
    use std::io::Write;
    let stdout = std::io::stdout();
    let mut lock = stdout.lock();
    match lock.write_all(s.as_bytes()) {
        Ok(()) => true,
        Err(e) if e.kind() == std::io::ErrorKind::BrokenPipe => false,
        Err(_) => false,
    }
}

fn main() -> ExitCode {
    let mut args = std::env::args().skip(1);
    let mut files = Vec::new();
    let mut summary = false;
    let mut histogram = false;
    let mut opts = Options::default();

    while let Some(a) = args.next() {
        match a.as_str() {
            "--summary" => summary = true,
            "--opcodes" => histogram = true,
            "--brief" => opts.verbose = false,
            "-h" | "--help" => {
                eprintln!("usage: koredis [--summary] [--brief] <file>...");
                return ExitCode::SUCCESS;
            }
            _ => files.push(a),
        }
    }

    if files.is_empty() {
        eprintln!("usage: koredis [--summary] [--brief] <file>...");
        return ExitCode::FAILURE;
    }

    let mut failed = 0usize;
    let mut counts = [0u64; 128];
    for path in &files {
        let data = match std::fs::read(path) {
            Ok(d) => d,
            Err(e) => {
                eprintln!("{path}: {e}");
                failed += 1;
                continue;
            }
        };
        match korevm::parse(&data) {
            Ok(c) => {
                if histogram {
                    let mut protos = Vec::new();
                    c.main.walk(&mut protos);
                    for p in protos {
                        for ins in &p.code {
                            counts[ins.opcode() as usize] += 1;
                        }
                    }
                } else if summary {
                    let mut protos = Vec::new();
                    c.main.walk(&mut protos);
                    let instrs: usize = protos.iter().map(|p| p.code.len()).sum();
                    let trailing = data.len() - c.size;
                    println!(
                        "ok\t{path}\t{} protos\t{instrs} instrs\t{} trailing bytes\t{}",
                        protos.len(),
                        trailing,
                        c.main.source
                    );
                } else {
                    if !write_out(&disasm::chunk(&c, &opts)) { return ExitCode::SUCCESS; }
                }
            }
            Err(e) => {
                if summary {
                    println!("FAIL\t{path}\t{e}");
                } else {
                    eprintln!("{path}: {e}");
                }
                failed += 1;
            }
        }
    }

    if histogram {
        for (op, n) in counts.iter().enumerate() {
            let name = korevm::OPCODES.get(op).map(|i| i.name).unwrap_or("<undefined>");
            println!("{op}\t{name}\t{n}");
        }
    }

    if failed > 0 {
        eprintln!("{failed} of {} file(s) failed", files.len());
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}
