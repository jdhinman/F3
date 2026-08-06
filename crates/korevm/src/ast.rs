//! Lua syntax tree and pretty printer.
//!
//! This is the decompiler's output side: the structuring pass builds these nodes, and
//! `render` turns them back into source text with correct precedence and parenthesisation.

use std::fmt::Write;

#[derive(Clone, Debug)]
pub struct FuncBody {
    pub params: Vec<String>,
    pub is_vararg: bool,
    pub body: Vec<Stmt>,
}

#[derive(Clone, Debug)]
pub enum Expr {
    Nil,
    Bool(bool),
    Number(f32),
    Str(Vec<u8>),
    Vararg,
    /// A named local, upvalue or global. Globals carry no prefix in Lua source.
    Name(String),
    Global(String),
    Index(Box<Expr>, Box<Expr>),
    Call(Box<Expr>, Vec<Expr>),
    Method(Box<Expr>, String, Vec<Expr>),
    Binop(&'static str, Box<Expr>, Box<Expr>),
    Unop(&'static str, Box<Expr>),
    Concat(Vec<Expr>),
    Table { array: Vec<Expr>, hash: Vec<(Expr, Expr)> },
    Function(Box<FuncBody>),
    /// A register whose contents could not be recovered. Printed as-is so the output
    /// stays readable, and counted as a defect rather than passed off as source.
    Unknown(String),
    /// Placeholder occupying the extra result registers of a multiple-return call.
    MultiRest,
}

#[derive(Clone, Debug)]
pub enum Stmt {
    Local(Vec<String>, Vec<Expr>),
    Assign(Vec<Expr>, Vec<Expr>),
    Call(Expr),
    If(Vec<(Expr, Vec<Stmt>)>, Option<Vec<Stmt>>),
    While(Expr, Vec<Stmt>),
    Repeat(Vec<Stmt>, Expr),
    NumericFor { var: String, start: Expr, limit: Expr, step: Expr, body: Vec<Stmt> },
    GenericFor { vars: Vec<String>, exprs: Vec<Expr>, body: Vec<Stmt> },
    Return(Vec<Expr>),
    Break,
    Do(Vec<Stmt>),
    /// Something the structuring pass could not turn into a statement. Emitted as a
    /// comment so the output is still valid Lua and the gap is visible.
    Note(String),
}

// Operator priorities, taken from Lua 5.1's lcode.c. Left and right differ for the
// right-associative operators.
fn binop_prec(op: &str) -> (u8, u8) {
    match op {
        "or" => (1, 1),
        "and" => (2, 2),
        "==" | "~=" | "<" | "<=" | ">" | ">=" => (3, 3),
        ".." => (9, 8),
        "+" | "-" => (10, 10),
        "*" | "/" | "%" => (11, 11),
        "^" => (14, 13),
        _ => (10, 10),
    }
}

const UNARY_PRIORITY: u8 = 12;
const PRIMARY: u8 = 100;

pub fn is_name(s: &str) -> bool {
    !s.is_empty()
        && !s.starts_with(|c: char| c.is_ascii_digit())
        && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
        && !matches!(
            s,
            "and" | "break" | "do" | "else" | "elseif" | "end" | "false" | "for" | "function"
                | "if" | "in" | "local" | "nil" | "not" | "or" | "repeat" | "return" | "then"
                | "true" | "until" | "while"
        )
}

fn number(n: f32) -> String {
    if n.is_nan() {
        return "(0/0)".into();
    }
    if n.is_infinite() {
        return if n > 0.0 { "(1/0)".into() } else { "(-1/0)".into() };
    }
    if n.fract() == 0.0 && n.abs() < 1e15 {
        format!("{}", n as i64)
    } else {
        format!("{n}")
    }
}

fn quote(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() + 2);
    s.push('"');
    for &b in bytes {
        match b {
            b'"' => s.push_str("\\\""),
            b'\\' => s.push_str("\\\\"),
            b'\n' => s.push_str("\\n"),
            b'\r' => s.push_str("\\r"),
            b'\t' => s.push_str("\\t"),
            0 => s.push_str("\\0"),
            0x20..=0x7e => s.push(b as char),
            _ => {
                let _ = write!(s, "\\{b}");
            }
        }
    }
    s.push('"');
    s
}

struct Printer {
    out: String,
    indent: usize,
}

impl Printer {
    fn line(&mut self, s: &str) {
        for _ in 0..self.indent {
            self.out.push_str("    ");
        }
        self.out.push_str(s);
        self.out.push('\n');
    }

    fn expr(&mut self, e: &Expr, limit: u8) -> String {
        let mut s = String::new();
        self.write_expr(&mut s, e, limit);
        s
    }

    fn write_expr(&mut self, out: &mut String, e: &Expr, limit: u8) {
        match e {
            Expr::Nil => out.push_str("nil"),
            Expr::Bool(b) => out.push_str(if *b { "true" } else { "false" }),
            Expr::Number(n) => out.push_str(&number(*n)),
            Expr::Str(s) => out.push_str(&quote(s)),
            Expr::Vararg => out.push_str("..."),
            Expr::Name(n) | Expr::Global(n) => out.push_str(n),
            Expr::Unknown(n) => out.push_str(n),
            Expr::MultiRest => out.push_str("nil"),
            Expr::Index(t, k) => {
                self.write_base(out, t);
                match &**k {
                    Expr::Str(s) if is_name(&String::from_utf8_lossy(s)) => {
                        out.push('.');
                        out.push_str(&String::from_utf8_lossy(s));
                    }
                    _ => {
                        out.push('[');
                        self.write_expr(out, k, 0);
                        out.push(']');
                    }
                }
            }
            Expr::Call(f, args) => {
                self.write_base(out, f);
                self.write_args(out, args);
            }
            Expr::Method(obj, name, args) => {
                self.write_base(out, obj);
                out.push(':');
                out.push_str(name);
                self.write_args(out, args);
            }
            Expr::Binop(op, a, b) => {
                let (l, r) = binop_prec(op);
                let paren = l < limit;
                if paren {
                    out.push('(');
                }
                // Left-associative operators need the tighter limit on the right,
                // right-associative ones on the left.
                let (ll, rl) = if l == r { (l, r + 1) } else { (l + 1, r) };
                self.write_expr(out, a, ll);
                let _ = write!(out, " {op} ");
                self.write_expr(out, b, rl);
                if paren {
                    out.push(')');
                }
            }
            Expr::Unop(op, a) => {
                let paren = UNARY_PRIORITY < limit;
                if paren {
                    out.push('(');
                }
                out.push_str(op);
                if *op == "not" || *op == "#" {
                    if *op == "not" {
                        out.push(' ');
                    }
                } else {
                    // Guard against "- -x" collapsing into a comment.
                    let mut inner = String::new();
                    self.write_expr(&mut inner, a, UNARY_PRIORITY);
                    if inner.starts_with('-') {
                        out.push(' ');
                    }
                    out.push_str(&inner);
                    if paren {
                        out.push(')');
                    }
                    return;
                }
                self.write_expr(out, a, UNARY_PRIORITY);
                if paren {
                    out.push(')');
                }
            }
            Expr::Concat(parts) => {
                let (l, r) = binop_prec("..");
                let paren = l < limit;
                if paren {
                    out.push('(');
                }
                for (i, p) in parts.iter().enumerate() {
                    if i > 0 {
                        out.push_str(" .. ");
                    }
                    self.write_expr(out, p, if i + 1 == parts.len() { r } else { l + 1 });
                }
                if paren {
                    out.push(')');
                }
            }
            Expr::Table { array, hash } => self.write_table(out, array, hash),
            Expr::Function(f) => self.write_function(out, None, f),
        }
    }

    /// A call or index base that is not already a primary expression needs parentheses.
    fn write_base(&mut self, out: &mut String, e: &Expr) {
        let needs = matches!(
            e,
            Expr::Binop(..)
                | Expr::Unop(..)
                | Expr::Concat(..)
                | Expr::Number(..)
                | Expr::Str(..)
                | Expr::Table { .. }
                | Expr::Function(..)
                | Expr::Nil
                | Expr::Bool(..)
                | Expr::Vararg
        );
        if needs {
            out.push('(');
            self.write_expr(out, e, 0);
            out.push(')');
        } else {
            self.write_expr(out, e, PRIMARY);
        }
    }

    fn write_args(&mut self, out: &mut String, args: &[Expr]) {
        out.push('(');
        for (i, a) in args.iter().enumerate() {
            if i > 0 {
                out.push_str(", ");
            }
            self.write_expr(out, a, 0);
        }
        out.push(')');
    }

    fn write_table(&mut self, out: &mut String, array: &[Expr], hash: &[(Expr, Expr)]) {
        if array.is_empty() && hash.is_empty() {
            out.push_str("{}");
            return;
        }
        let mut parts: Vec<String> = Vec::new();
        for a in array {
            parts.push(self.expr(a, 0));
        }
        for (k, v) in hash {
            let key = match k {
                Expr::Str(s) if is_name(&String::from_utf8_lossy(s)) => {
                    String::from_utf8_lossy(s).into_owned()
                }
                other => format!("[{}]", self.expr(other, 0)),
            };
            parts.push(format!("{key} = {}", self.expr(v, 0)));
        }
        let oneline = format!("{{ {} }}", parts.join(", "));
        if oneline.len() + self.indent * 4 <= 100 && !oneline.contains('\n') {
            out.push_str(&oneline);
            return;
        }
        out.push_str("{\n");
        self.indent += 1;
        for p in &parts {
            for _ in 0..self.indent {
                out.push_str("    ");
            }
            out.push_str(p);
            out.push_str(",\n");
        }
        self.indent -= 1;
        for _ in 0..self.indent {
            out.push_str("    ");
        }
        out.push('}');
    }

    /// `head` is the `function <name>` prefix for a function statement; None for a
    /// function expression.
    fn write_function(&mut self, out: &mut String, head: Option<&str>, f: &FuncBody) {
        let mut params: Vec<String> = f.params.clone();
        if f.is_vararg {
            params.push("...".into());
        }
        let _ = write!(out, "function{}({})", head.unwrap_or(""), params.join(", "));
        let body = self.render_block(&f.body, self.indent + 1);
        out.push('\n');
        out.push_str(&body);
        for _ in 0..self.indent {
            out.push_str("    ");
        }
        out.push_str("end");
    }

    fn render_block(&mut self, stmts: &[Stmt], indent: usize) -> String {
        let mut sub = Printer { out: String::new(), indent };
        sub.block(stmts);
        sub.out
    }

    fn block(&mut self, stmts: &[Stmt]) {
        for s in stmts {
            self.stmt(s);
        }
    }

    fn stmt(&mut self, s: &Stmt) {
        match s {
            Stmt::Note(msg) => {
                for line in msg.lines() {
                    self.line(&format!("-- {line}"));
                }
            }
            Stmt::Local(names, values) => {
                if values.is_empty() {
                    self.line(&format!("local {}", names.join(", ")));
                } else if let (1, 1, Some(Expr::Function(f))) =
                    (names.len(), values.len(), values.first())
                {
                    // `local f = function() end` reads better as `local function f()`.
                    let f = f.clone();
                    let mut head = String::new();
                    self.write_function(&mut head, Some(&format!(" {}", names[0])), &f);
                    self.emit_multiline(&format!("local {head}"));
                } else {
                    let vs: Vec<String> = values.iter().map(|v| self.expr(v, 0)).collect();
                    self.emit_multiline(&format!("local {} = {}", names.join(", "), vs.join(", ")));
                }
            }
            Stmt::Assign(targets, values) => {
                if let (1, 1, Some(Expr::Function(f))) =
                    (targets.len(), values.len(), values.first())
                {
                    if let Some(text) = self.function_statement(&targets[0], f) {
                        self.emit_multiline(&text);
                        return;
                    }
                }
                let ts: Vec<String> = targets.iter().map(|t| self.expr(t, 0)).collect();
                let vs: Vec<String> = values.iter().map(|v| self.expr(v, 0)).collect();
                self.emit_multiline(&format!("{} = {}", ts.join(", "), vs.join(", ")));
            }
            Stmt::Call(e) => {
                let text = self.expr(e, 0);
                self.emit_multiline(&text);
            }
            Stmt::Return(values) => {
                if values.is_empty() {
                    self.line("return");
                } else {
                    let vs: Vec<String> = values.iter().map(|v| self.expr(v, 0)).collect();
                    self.emit_multiline(&format!("return {}", vs.join(", ")));
                }
            }
            Stmt::Break => self.line("break"),
            Stmt::Do(body) => {
                self.line("do");
                self.indent += 1;
                self.block(body);
                self.indent -= 1;
                self.line("end");
            }
            Stmt::If(arms, els) => {
                for (i, (cond, body)) in arms.iter().enumerate() {
                    let c = self.expr(cond, 0);
                    self.line(&format!("{} {c} then", if i == 0 { "if" } else { "elseif" }));
                    self.indent += 1;
                    self.block(body);
                    self.indent -= 1;
                }
                if let Some(e) = els {
                    self.line("else");
                    self.indent += 1;
                    self.block(e);
                    self.indent -= 1;
                }
                self.line("end");
            }
            Stmt::While(cond, body) => {
                let c = self.expr(cond, 0);
                self.line(&format!("while {c} do"));
                self.indent += 1;
                self.block(body);
                self.indent -= 1;
                self.line("end");
            }
            Stmt::Repeat(body, cond) => {
                self.line("repeat");
                self.indent += 1;
                self.block(body);
                self.indent -= 1;
                let c = self.expr(cond, 0);
                self.line(&format!("until {c}"));
            }
            Stmt::NumericFor { var, start, limit, step, body } => {
                let (a, b) = (self.expr(start, 0), self.expr(limit, 0));
                let head = match step {
                    Expr::Number(n) if *n == 1.0 => format!("for {var} = {a}, {b} do"),
                    other => {
                        let c = self.expr(other, 0);
                        format!("for {var} = {a}, {b}, {c} do")
                    }
                };
                self.line(&head);
                self.indent += 1;
                self.block(body);
                self.indent -= 1;
                self.line("end");
            }
            Stmt::GenericFor { vars, exprs, body } => {
                let es: Vec<String> = exprs.iter().map(|e| self.expr(e, 0)).collect();
                self.line(&format!("for {} in {} do", vars.join(", "), es.join(", ")));
                self.indent += 1;
                self.block(body);
                self.indent -= 1;
                self.line("end");
            }
        }
    }

    /// Renders `function Name()` / `function t.k()` / `function t:k()` when the target
    /// allows it, so closures assigned to a name read like declarations.
    fn function_statement(&mut self, target: &Expr, f: &FuncBody) -> Option<String> {
        let mut f = f.clone();
        let head = match target {
            Expr::Name(n) | Expr::Global(n) if is_name(n) => format!(" {n}"),
            Expr::Index(base, key) => {
                let name = match &**key {
                    Expr::Str(s) if is_name(&String::from_utf8_lossy(s)) => {
                        String::from_utf8_lossy(s).into_owned()
                    }
                    _ => return None,
                };
                let base_text = self.expr(base, PRIMARY);
                if !base_text.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.') {
                    return None;
                }
                if f.params.first().map(|p| p == "self").unwrap_or(false) {
                    f.params.remove(0);
                    format!(" {base_text}:{name}")
                } else {
                    format!(" {base_text}.{name}")
                }
            }
            _ => return None,
        };
        let mut out = String::new();
        self.write_function(&mut out, Some(&head), &f);
        Some(out)
    }

    /// Writes text that may already contain newlines (a nested function body), keeping
    /// the first line indented and the rest as produced.
    fn emit_multiline(&mut self, text: &str) {
        let mut lines = text.split('\n');
        if let Some(first) = lines.next() {
            self.line(first);
        }
        for l in lines {
            self.out.push_str(l);
            self.out.push('\n');
        }
    }
}

pub fn render(stmts: &[Stmt]) -> String {
    let mut p = Printer { out: String::new(), indent: 0 };
    p.block(stmts);
    p.out
}
