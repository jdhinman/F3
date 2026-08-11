//! fnvpre: build a printable alias string whose FNV-1 hash equals a target.
//!
//!   fnvpre <hex-hash> [more hashes...]
//!
//! The GDB name map keys objects by FNV-1(name), so any preimage of the hash names the
//! same object. Meet-in-the-middle over a lowercase+digit+underscore alphabet: forward
//! 4 chars from the FNV basis, backward 4 chars from the target through the inverted
//! step (the prime is odd, so it has an inverse mod 2^32). Output is an 8-char alias.

use std::collections::HashMap;
use std::process::ExitCode;

const PRIME: u32 = 0x0100_0193;
// PRIME * PRIME_INV = 1 mod 2^32
const PRIME_INV: u32 = 0x359c_449b;
const BASIS: u32 = 0x811c_9dc5;
const ALPHA: &[u8] = b"abcdefghijklmnopqrstuvwxyz0123456789_";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.is_empty() {
        eprintln!("usage: fnvpre <hex-hash> [hex-hash...]");
        return ExitCode::FAILURE;
    }

    // forward half: every state reachable from the basis in 4 chars
    let mut fwd: HashMap<u32, [u8; 4]> = HashMap::with_capacity(ALPHA.len().pow(4));
    for &a in ALPHA {
        let ha = BASIS.wrapping_mul(PRIME) ^ a as u32;
        for &b in ALPHA {
            let hb = ha.wrapping_mul(PRIME) ^ b as u32;
            for &c in ALPHA {
                let hc = hb.wrapping_mul(PRIME) ^ c as u32;
                for &d in ALPHA {
                    let hd = hc.wrapping_mul(PRIME) ^ d as u32;
                    fwd.entry(hd).or_insert([a, b, c, d]);
                }
            }
        }
    }

    for arg in &args {
        let Ok(target) = u32::from_str_radix(arg.trim_start_matches("0x"), 16) else {
            eprintln!("{arg}: not a hex hash");
            continue;
        };
        let mut found = None;
        'search: for &a in ALPHA {
            let ha = (target ^ a as u32).wrapping_mul(PRIME_INV);
            for &b in ALPHA {
                let hb = (ha ^ b as u32).wrapping_mul(PRIME_INV);
                for &c in ALPHA {
                    let hc = (hb ^ c as u32).wrapping_mul(PRIME_INV);
                    for &d in ALPHA {
                        let hd = (hc ^ d as u32).wrapping_mul(PRIME_INV);
                        if let Some(pre) = fwd.get(&hd) {
                            found = Some([pre[0], pre[1], pre[2], pre[3], d, c, b, a]);
                            break 'search;
                        }
                    }
                }
            }
        }
        match found {
            Some(s) => {
                let alias = std::str::from_utf8(&s).unwrap();
                // verify before printing; a wrong alias in game costs an entity
                let mut h = BASIS;
                for &ch in &s {
                    h = h.wrapping_mul(PRIME) ^ ch as u32;
                }
                if h == target {
                    println!("{target:08X} {alias}");
                } else {
                    eprintln!("{target:08X} INTERNAL ERROR alias {alias} hashes to {h:08X}");
                    return ExitCode::FAILURE;
                }
            }
            None => eprintln!("{target:08X} no 8-char alias found"),
        }
    }
    ExitCode::SUCCESS
}
