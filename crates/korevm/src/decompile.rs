//! The decompiler back end: bytecode -> Lua source.
//!
//! Four passes, run together over each proto:
//!
//! 1. **Lowering.** The 87 KoreVM opcodes collapse onto Lua 5.1's core operations. The
//!    specialised forms (`GETFIELD`, `GETTABLE_S`, `GETFIELD_R1`, `_BK`, `_R1`, `CALL_I`...)
//!    differ only in how they fetch their operands, so they are matched by name and lowered
//!    to the same handful of cases.
//! 2. **Expression rebuild.** Registers hold expressions rather than values. Debug info tells
//!    us which registers are named locals at each pc; writes to those become statements,
//!    writes to anything else accumulate into larger expressions.
//! 3. **Structuring.** Loops come from back edges, conditionals from the test-then-jump idiom.
//!    Ranges are decompiled recursively.
//! 4. **Naming.** Locals, parameters and upvalues come straight out of the debug data that
//!    `gamescripts.bnk` retains.
//!
//! Where a construct cannot be recovered the output carries a `-- [decompiler]` note rather
//! than a plausible-looking guess, and the note is counted in `Output::notes`.

use crate::ast::{is_name, Expr, FuncBody, Stmt};
use crate::chunk::{Constant, Proto};
use crate::opcodes::{index_k, is_k, Instruction};

pub struct Output {
    pub body: Vec<Stmt>,
    /// One entry per construct the decompiler could not recover. Empty means the whole
    /// function was structured; a non-empty list is the honest defect count.
    pub notes: Vec<String>,
}

pub fn proto(p: &Proto) -> Output {
    let mut d = Decompiler::new(p);
    let body = d.function_body();
    Output { body, notes: d.notes }
}

/// Convenience: decompile a whole chunk, with a header comment naming the source file.
pub fn chunk(c: &crate::chunk::Chunk) -> Output {
    let mut out = proto(&c.main);
    if !c.main.source.is_empty() {
        out.body.insert(0, Stmt::Note(format!("source: {}", c.main.source)));
    }
    out
}

struct Decompiler<'a> {
    p: &'a Proto,
    /// Current expression held by each register.
    regs: Vec<Option<Expr>>,
    /// Registers loaded by SELF, i.e. holding a method about to be called with its
    /// receiver already duplicated into the next register.
    method_regs: Vec<bool>,
    /// Highest register written plus one, for the "to top" forms of CALL/RETURN/SETLIST.
    top: usize,
    /// Statements accumulated for the block currently being built.
    out: Vec<Stmt>,
    /// Locals already emitted as declarations, indexed by locvar.
    declared: Vec<bool>,
    /// Exit pc of each enclosing loop, for recognising `break`.
    loop_exits: Vec<usize>,
    /// Loop headers currently being decompiled, so a header is not claimed twice.
    active_heads: Vec<usize>,
    /// Register currently receiving the value of an `and`/`or` expression.
    value_target: Option<usize>,
    /// Every pc that counts as leaving the current nesting normally: the end of each
    /// enclosing block, and where each enclosing structure hands control on afterwards.
    /// The compiler chains jumps, so a branch nested several blocks deep routinely jumps
    /// straight to one of these rather than to the end of its own block.
    enclosing_ends: Vec<usize>,
    /// For each pc, the jumps that come back to it. Loop headers are exactly the pcs with
    /// a non-empty entry.
    back_sources: Vec<Vec<usize>>,
    notes: Vec<String>,
}

impl<'a> Decompiler<'a> {
    fn new(p: &'a Proto) -> Self {
        let mut back_sources = vec![Vec::new(); p.code.len() + 1];
        for (i, ins) in p.code.iter().enumerate() {
            if ins.info().map(|x| x.name) == Some("JMP") {
                let t = (i as i64 + 1 + ins.sbx() as i64).max(0) as usize;
                if t < i && t < back_sources.len() {
                    back_sources[t].push(i);
                }
            }
        }
        Decompiler {
            back_sources,
            p,
            regs: vec![None; p.max_stack_size as usize + 8],
            method_regs: vec![false; p.max_stack_size as usize + 8],
            top: 0,
            out: Vec::new(),
            declared: vec![false; p.locvars.len()],
            loop_exits: Vec::new(),
            active_heads: Vec::new(),
            value_target: None,
            enclosing_ends: Vec::new(),
            notes: Vec::new(),
        }
    }

    fn note(&mut self, msg: String) {
        self.notes.push(msg.clone());
        self.out.push(Stmt::Note(format!("[decompiler] {msg}")));
    }

    // ---- debug info ----------------------------------------------------------------

    /// Locvar indices active at `pc`, in register order. Mirrors `luaF_getlocalname`.
    fn active(&self, pc: usize) -> Vec<usize> {
        let mut v = Vec::new();
        for (i, lv) in self.p.locvars.iter().enumerate() {
            if lv.startpc as usize > pc {
                break;
            }
            if pc < lv.endpc as usize {
                v.push(i);
            }
        }
        v
    }

    fn local_at(&self, r: usize, pc: usize) -> Option<usize> {
        self.active(pc).get(r).copied()
    }

    /// Compiler-generated locals (`(for index)`, `(for state)`...) occupy registers but are
    /// not user variables, so they must never be named or assigned in the output.
    fn is_internal(name: &str) -> bool {
        name.starts_with('(')
    }

    /// Does any local's scope begin within `[lo, hi]`?
    fn local_starts_in(&self, lo: usize, hi: usize) -> bool {
        self.p.locvars.iter().any(|lv| {
            let s = lv.startpc as usize;
            s >= lo && s <= hi
        })
    }

    fn local_name(&self, r: usize, pc: usize) -> Option<String> {
        let i = self.local_at(r, pc)?;
        let n = &self.p.locvars[i].name;
        if Self::is_internal(n) {
            None
        } else {
            Some(n.clone())
        }
    }

    fn upvalue(&self, i: usize) -> Expr {
        match self.p.upvalues.get(i) {
            Some(n) if !n.is_empty() => Expr::Name(n.clone()),
            _ => Expr::Unknown(format!("upvalue_{i}")),
        }
    }

    // ---- registers and operands ----------------------------------------------------

    fn set_reg(&mut self, r: usize, e: Expr) {
        if r >= self.regs.len() {
            self.regs.resize(r + 1, None);
        }
        if r < self.method_regs.len() {
            self.method_regs[r] = false;
        } else {
            self.method_regs.resize(r + 1, false);
        }
        self.regs[r] = Some(e);
        if r + 1 > self.top {
            self.top = r + 1;
        }
    }

    fn reg(&self, r: usize, pc: usize) -> Expr {
        if let Some(n) = self.local_name(r, pc) {
            return Expr::Name(n);
        }
        match self.regs.get(r).and_then(|x| x.clone()) {
            Some(e) => e,
            None => Expr::Unknown(format!("R{r}")),
        }
    }

    fn konst(&self, i: usize) -> Expr {
        match self.p.constants.get(i) {
            Some(Constant::Nil) | None => Expr::Nil,
            Some(Constant::Bool(b)) => Expr::Bool(*b),
            Some(Constant::Number(n)) => Expr::Number(*n),
            Some(Constant::Str(s)) => Expr::Str(s.clone()),
        }
    }

    /// Register-or-constant. Only C can carry the RK bit: B is 8 bits wide and cannot
    /// reach BITRK, which is exactly why the `_BK` opcodes exist.
    fn rk(&self, x: u32, pc: usize) -> Expr {
        if is_k(x) {
            self.konst(index_k(x) as usize)
        } else {
            self.reg(x as usize, pc)
        }
    }

    fn index(&self, table: Expr, key: Expr) -> Expr {
        Expr::Index(Box::new(table), Box::new(key))
    }

    // ---- statement emission --------------------------------------------------------

    /// Assign to a register: a statement if the register is a live named local, otherwise
    /// the value just accumulates for whatever consumes it later.
    fn assign(&mut self, r: usize, e: Expr, pc: usize) {
        // While building the right-hand side of an `and`/`or`, writes to the destination
        // are part of the expression, not an assignment of their own.
        if self.value_target == Some(r) {
            self.set_reg(r, e);
            return;
        }
        if let Some(i) = self.local_at(r, pc) {
            if self.declared[i] && !Self::is_internal(&self.p.locvars[i].name) {
                let name = self.p.locvars[i].name.clone();
                self.out.push(Stmt::Assign(vec![Expr::Name(name.clone())], vec![e]));
                self.set_reg(r, Expr::Name(name));
                return;
            }
        }
        self.set_reg(r, e);
    }

    /// Emit `local a, b = ...` for any locals whose scope begins at `pc`. Their values are
    /// already sitting in the registers, put there by the instructions just executed.
    fn declare_locals_at(&mut self, pc: usize) {
        let active = self.active(pc);
        let mut group: Vec<(usize, usize)> = Vec::new(); // (register, locvar index)
        for (reg, &li) in active.iter().enumerate() {
            if self.declared[li] || self.p.locvars[li].startpc as usize != pc {
                continue;
            }
            if Self::is_internal(&self.p.locvars[li].name) {
                self.declared[li] = true;
                continue;
            }
            group.push((reg, li));
        }
        if group.is_empty() {
            return;
        }
        let mut names = Vec::new();
        let mut values = Vec::new();
        for &(reg, li) in &group {
            self.declared[li] = true;
            names.push(self.p.locvars[li].name.clone());
            // A MultiRest register is an extra result of the call in an earlier register,
            // so it contributes a name but no value expression.
            match self.regs.get(reg).and_then(|x| x.clone()) {
                Some(Expr::MultiRest) => {}
                Some(e) => values.push(e),
                None => values.push(Expr::Nil),
            }
        }
        for &(reg, li) in &group {
            let name = self.p.locvars[li].name.clone();
            self.set_reg(reg, Expr::Name(name));
        }
        self.out.push(Stmt::Local(names, values));
    }

    // ---- top level -----------------------------------------------------------------

    fn function_body(&mut self) -> Vec<Stmt> {
        // Parameters occupy the first registers and are live from pc 0.
        for i in 0..self.p.num_params as usize {
            if let Some(li) = self.local_at(i, 0) {
                self.declared[li] = true;
                let name = self.p.locvars[li].name.clone();
                self.set_reg(i, Expr::Name(name));
            }
        }
        self.top = self.p.num_params as usize;
        let n = self.p.code.len();
        let mut body = self.block(0, n);
        // Every function ends in a RETURN the source did not write.
        if matches!(body.last(), Some(Stmt::Return(v)) if v.is_empty()) {
            body.pop();
        }
        body
    }

    fn params(&self) -> Vec<String> {
        (0..self.p.num_params as usize)
            .map(|i| match self.local_at(i, 0) {
                Some(li) if !Self::is_internal(&self.p.locvars[li].name) => {
                    self.p.locvars[li].name.clone()
                }
                _ => format!("arg{}", i + 1),
            })
            .collect()
    }

    // ---- control flow --------------------------------------------------------------

    fn op(&self, pc: usize) -> &'static str {
        self.p.code.get(pc).and_then(|i| i.info()).map(|i| i.name).unwrap_or("")
    }

    fn ins(&self, pc: usize) -> Instruction {
        self.p.code.get(pc).copied().unwrap_or(Instruction(0))
    }

    fn jump_target(&self, pc: usize) -> usize {
        (pc as i64 + 1 + self.ins(pc).sbx() as i64).max(0) as usize
    }

    fn is_cond(&self, pc: usize) -> bool {
        matches!(
            self.op(pc),
            "EQ" | "EQ_BK" | "LT" | "LT_BK" | "LE" | "LE_BK" | "TEST" | "TEST_R1" | "TESTSET"
        ) && self.op(pc + 1) == "JMP"
    }

    /// Decompile the instruction range `[start, end)` into a statement list.
    fn block(&mut self, start: usize, end: usize) -> Vec<Stmt> {
        let saved = std::mem::take(&mut self.out);
        self.enclosing_ends.push(end);
        let mut pc = start;
        while pc < end {
            self.declare_locals_at(pc);
            let next = self.step(pc, end);
            pc = if next > pc { next } else { pc + 1 };
        }
        self.enclosing_ends.pop();
        let mut body = std::mem::replace(&mut self.out, saved);
        seal_terminators(&mut body);
        body
    }

    fn step(&mut self, pc: usize, end: usize) -> usize {
        // A loop header is any pc that a later jump comes back to. A `while true` body
        // starts at its own header, so a header already being processed must not be
        // claimed again: it would nest the loop inside itself against an earlier back
        // edge and swallow the real structure.
        if !self.active_heads.contains(&pc) {
            if let Some(last) = self.back_edge_into(pc, end) {
                return self.loop_at(pc, last);
            }
        }
        match self.op(pc) {
            "FORPREP" => self.numeric_for(pc),
            "JMP" => self.jump(pc, end),
            _ if self.is_cond(pc) => self.conditional(pc, end),
            _ => self.simple(pc),
        }
    }

    /// The furthest instruction in `[pc, end)` that jumps backwards to `pc`.
    fn back_edge_into(&self, pc: usize, end: usize) -> Option<usize> {
        self.back_sources
            .get(pc)?
            .iter()
            .copied()
            .filter(|&s| s > pc && s < end)
            .max()
    }

    fn is_loop_head(&self, pc: usize, end: usize) -> bool {
        self.back_edge_into(pc, end).is_some()
    }

    /// Follow a chain of unconditional jumps to where control actually ends up. The
    /// compiler routinely retargets a branch straight at the end of the chain, so two
    /// targets that look different can be the same place.
    fn resolve(&self, t: usize) -> usize {
        let mut cur = t;
        for _ in 0..32 {
            if self.op(cur) != "JMP" {
                break;
            }
            let next = self.jump_target(cur);
            if next == cur {
                break;
            }
            cur = next;
        }
        cur
    }

    /// Does control reaching `t` amount to leaving the current nesting normally?
    fn is_normal_exit(&self, t: usize) -> bool {
        let r = self.resolve(t);
        t == self.p.code.len()
            || r == self.p.code.len()
            || self.enclosing_ends.iter().any(|&e| e == t || self.resolve(e) == r)
            || self.loop_exits.iter().any(|&e| e == t || self.resolve(e) == r)
    }

    fn loop_at(&mut self, head: usize, back: usize) -> usize {
        let exit = back + 1;
        self.loop_exits.push(exit);
        self.active_heads.push(head);

        // `while cond do` puts the test at the head, jumping past the back edge when false.
        if self.is_cond(head) {
            if let Some((tests, then_start, false_target)) = self.scan_conds(head, back) {
                if false_target == exit || self.resolve(false_target) == self.resolve(exit) {
                    let cond = self.build_conds(&tests, then_start);
                    let body = self.block(then_start, back);
                    self.loop_exits.pop();
                    self.active_heads.pop();
                    self.out.push(Stmt::While(cond, body));
                    return exit;
                }
            }
        }
        // `repeat ... until cond` puts the test just before the back edge, jumping back to
        // the head when the condition is false. The chain can start several instructions
        // earlier, so find the earliest start that still ends on the back edge.
        if back > head {
            let mut best = None;
            for s in (head + 1..back).rev() {
                if !self.is_cond(s) {
                    continue;
                }
                if let Some((tests, then_start, x)) = self.scan_conds(s, back + 1) {
                    if tests.last().map(|t| t.0) == Some(back - 1) && x == head && then_start == back + 1
                    {
                        best = Some((tests, then_start, s));
                    }
                }
            }
            if let Some((tests, then_start, s)) = best {
                let body = self.block(head, s);
                let cond = self.build_conds(&tests, then_start);
                self.loop_exits.pop();
                self.active_heads.pop();
                self.out.push(Stmt::Repeat(body, cond));
                return exit;
            }
        }
        // Generic `while true do`, which is also what a loop with only `break` exits becomes.
        let body = self.block(head, back);
        self.loop_exits.pop();
        self.active_heads.pop();
        self.out.push(Stmt::While(Expr::Bool(true), body));
        exit
    }

    fn numeric_for(&mut self, pc: usize) -> usize {
        let a = self.ins(pc).a() as usize;
        let forloop = self.jump_target(pc);
        let start = self.reg(a, pc);
        let limit = self.reg(a + 1, pc);
        let step = self.reg(a + 2, pc);
        // The user variable lives at A+3 and is named in the debug data.
        let var = self
            .local_name(a + 3, pc + 1)
            .unwrap_or_else(|| format!("i{}", a + 3));
        if let Some(li) = self.local_at(a + 3, pc + 1) {
            self.declared[li] = true;
        }
        self.set_reg(a + 3, Expr::Name(var.clone()));

        self.loop_exits.push(forloop + 1);
        let body = self.block(pc + 1, forloop);
        self.loop_exits.pop();
        self.out.push(Stmt::NumericFor { var, start, limit, step, body });
        forloop + 1
    }

    /// `for k, v in explist do`: a JMP into a TFORLOOP that sits at the bottom.
    fn generic_for(&mut self, pc: usize, tfor: usize) -> usize {
        let a = self.ins(tfor).a() as usize;
        let nvars = self.ins(tfor).c() as usize;
        // The three control values were built into A, A+1, A+2 before the jump.
        let mut exprs = Vec::new();
        for r in a..a + 3 {
            match self.regs.get(r).and_then(|x| x.clone()) {
                Some(Expr::MultiRest) | None => {}
                Some(e) => exprs.push(e),
            }
        }
        if exprs.is_empty() {
            exprs.push(Expr::Unknown(format!("R{a}")));
        }
        let mut vars = Vec::new();
        for i in 0..nvars.max(1) {
            let r = a + 3 + i;
            let name = self
                .local_name(r, tfor + 1)
                .unwrap_or_else(|| format!("v{r}"));
            if let Some(li) = self.local_at(r, tfor + 1) {
                self.declared[li] = true;
            }
            self.set_reg(r, Expr::Name(name.clone()));
            vars.push(name);
        }
        let exit = tfor + 2;
        self.loop_exits.push(exit);
        let body = self.block(pc + 1, tfor);
        self.loop_exits.pop();
        self.out.push(Stmt::GenericFor { vars, exprs, body });
        exit
    }

    fn jump(&mut self, pc: usize, end: usize) -> usize {
        let t = self.jump_target(pc);
        if t < self.p.code.len() && self.op(t) == "TFORLOOP" && t > pc && t <= end {
            return self.generic_for(pc, t);
        }
        if !self.loop_exits.is_empty() && self.loop_exits.last() == Some(&t) {
            self.out.push(Stmt::Break);
            return pc + 1;
        }
        if t <= pc {
            // Jumping back to the header of a loop we are inside is one more iteration.
            // The compiler produces these by retargeting the end of a nested `if` straight
            // at the loop top instead of letting control fall through to the back edge.
            if self.active_heads.contains(&t) {
                return pc + 1;
            }
            // A back edge no enclosing loop accounts for. Rather than invent a loop, say so.
            self.note(format!("unstructured backward jump at pc {pc} to {t}"));
            return pc + 1;
        }
        if t > end {
            // Leaving the block entirely: a break if there is a loop to break out of,
            // otherwise a boundary this pass got wrong.
            if self.loop_exits.contains(&t) {
                self.out.push(Stmt::Break);
            } else if !self.is_normal_exit(t) {
                self.note(format!("jump at pc {pc} leaves its block, to {t}"));
            }
            return pc + 1;
        }
        // A forward jump inside a block with no matching structure: skip the gap, but
        // record it, because silently dropping instructions is how decompilers lie.
        if t > pc + 1 {
            self.note(format!("unstructured forward jump at pc {pc} over {} instructions", t - pc - 1));
        }
        pc + 1
    }

    /// Find the run of tests that make up one condition, without evaluating anything.
    ///
    /// `a and b` is a run of tests that all jump to the same false exit. `a or b` mixes in
    /// tests that jump forward into the true branch instead. So a chain is exactly a run
    /// whose jump targets take only two values: the start of the true branch, and one
    /// shared exit. Anything else belongs to a nested structure and is left alone.
    ///
    /// Tests are not adjacent: the operands of the second test are computed between them,
    /// which is why this walks forward over value-producing instructions.
    ///
    /// Returns (tests as (pc, jump target), start of the true branch, the shared exit).
    fn scan_conds(&self, pc: usize, limit: usize) -> Option<(Vec<(usize, usize)>, usize, usize)> {
        let mut cands: Vec<(usize, usize)> = Vec::new();
        let mut i = pc;
        while cands.len() < 16 {
            let mut j = i;
            while j < limit && !self.is_cond(j) {
                if self.is_statement_like(j)
                    || self.op(j) == "JMP"
                    || self.op(j) == "CLOSURE"
                    || self.is_loop_head(j, limit)
                {
                    break;
                }
                j += 1;
            }
            if j >= limit || !self.is_cond(j) {
                break;
            }
            // A test that is also a loop header belongs to the loop, not to this chain.
            // Without this the `while i <= n do` test gets absorbed into the enclosing
            // `if` and the loop disappears.
            if j != pc && self.is_loop_head(j, limit) {
                break;
            }
            // `if a and b then X end` and `if a then if b then X end end` compile to the
            // same bytecode, so flattening is normally a fair reading. It stops being one
            // when a local is declared between the tests: a local cannot be declared
            // inside an expression, so there is a real block boundary there.
            if j != pc && self.local_starts_in(i, j) {
                break;
            }
            cands.push((j, self.jump_target(j + 1)));
            i = j + 2;
        }
        // Take the longest prefix that still looks like one condition.
        for k in (1..=cands.len()).rev() {
            let then_start = cands[k - 1].0 + 2;
            let others: Vec<usize> =
                cands[..k].iter().map(|c| c.1).filter(|&t| t != then_start).collect();
            let Some(&x) = others.first() else { continue };
            if others.iter().all(|&t| t == x) {
                return Some((cands[..k].to_vec(), then_start, x));
            }
        }
        None
    }

    /// Evaluate a scanned chain into one expression. This runs the instructions that sit
    /// between the tests, so it must be called exactly once per chain.
    fn build_conds(&mut self, tests: &[(usize, usize)], then_start: usize) -> Expr {
        let mut taken: Vec<(Expr, usize)> = Vec::new();
        for (idx, &(tpc, target)) in tests.iter().enumerate() {
            let mut j = if idx == 0 { tpc } else { tests[idx - 1].0 + 2 };
            while j < tpc {
                self.declare_locals_at(j);
                let next = self.simple(j);
                j = if next > j { next } else { j + 1 };
            }
            self.declare_locals_at(tpc);
            let cond = self.taken_condition(tpc);
            taken.push((cond, target));
        }
        // Build right to left: falling through the last test is the base case.
        let mut expr = negate(taken[taken.len() - 1].0.clone());
        for k in (0..taken.len() - 1).rev() {
            let (c, t) = taken[k].clone();
            expr = if t == then_start {
                Expr::Binop("or", Box::new(c), Box::new(expr))
            } else {
                Expr::Binop("and", Box::new(negate(c)), Box::new(expr))
            };
        }
        expr
    }

    /// The condition under which the jump following a test is taken.
    fn taken_condition(&mut self, pc: usize) -> Expr {
        let ins = self.ins(pc);
        let (a, b, c) = (ins.a(), ins.b(), ins.c());
        match self.op(pc) {
            "TEST" | "TEST_R1" => {
                // Jump when isfalse(R(A)) != C, so C=1 jumps on truthy.
                let v = self.reg(a as usize, pc);
                if c == 0 {
                    negate(v)
                } else {
                    v
                }
            }
            "TESTSET" => {
                let v = self.reg(b as usize, pc);
                if c == 0 {
                    negate(v)
                } else {
                    v
                }
            }
            name => {
                // Comparisons jump when the result equals A.
                let (lhs, rhs) = if name.ends_with("_BK") {
                    (self.konst(b as usize), self.rk(c, pc))
                } else {
                    (self.reg(b as usize, pc), self.rk(c, pc))
                };
                let op = match name {
                    "EQ" | "EQ_BK" => {
                        if a == 1 {
                            "=="
                        } else {
                            "~="
                        }
                    }
                    "LT" | "LT_BK" => {
                        if a == 1 {
                            "<"
                        } else {
                            ">="
                        }
                    }
                    "LE" | "LE_BK" => {
                        if a == 1 {
                            "<="
                        } else {
                            ">"
                        }
                    }
                    _ => "==",
                };
                Expr::Binop(op, Box::new(lhs), Box::new(rhs))
            }
        }
    }

    fn conditional(&mut self, pc: usize, end: usize) -> usize {
        // `x = a < b` materialises a comparison as a value via a LOADBOOL pair.
        if self.op(pc + 2) == "LOADBOOL" && self.ins(pc + 2).c() != 0 && self.jump_target(pc + 1) == pc + 3 {
            let cond = self.taken_condition(pc);
            let a = self.ins(pc + 2).a() as usize;
            self.assign(a, cond, pc + 3);
            return pc + 4;
        }
        // `x = a and b` / `a or b` as a value.
        if let Some(next) = self.try_value_condition(pc, end) {
            return next;
        }

        // A test whose branch lands on the very next instruction decides nothing. It is
        // what a condition evaluated only for its side effects compiles to, and those
        // side effects are already emitted by the instructions that fed it.
        if self.jump_target(pc + 1) == pc + 2 {
            return pc + 2;
        }
        let Some((tests, then_start, false_target)) = self.scan_conds(pc, end) else {
            self.note(format!("unrecognised condition shape at pc {pc}"));
            return pc + 2;
        };
        if false_target <= then_start || false_target > end {
            // Jumping past the end of this block is the same as reaching the end of it,
            // as long as the target is where an enclosing block hands control on. That is
            // the normal result of the compiler chaining jumps, not a failure.
            if !self.is_normal_exit(false_target) {
                self.note(format!(
                    "condition at pc {pc} jumps to {false_target}, past the end of its block"
                ));
            }
            let cond = self.build_conds(&tests, then_start);
            let body = self.block(then_start, end);
            self.out.push(Stmt::If(vec![(cond, body)], None));
            return end;
        }
        let cond = self.build_conds(&tests, then_start);

        // An `else` shows up as an unconditional forward jump closing the true branch,
        // but the same shape is a `break`, so check the enclosing loop first.
        let mut then_end = false_target;
        let mut else_range = None;
        if false_target > then_start && self.op(false_target - 1) == "JMP" {
            let e = self.jump_target(false_target - 1);
            let is_break = self.loop_exits.last() == Some(&e);
            if e > false_target && e <= end && !is_break {
                then_end = false_target - 1;
                else_range = Some((false_target, e));
            }
        }

        // Inside the true branch, jumping to where the whole if/else finishes is a normal
        // exit, not a defect.
        if let Some((_, e)) = else_range {
            self.enclosing_ends.push(e);
        }
        let then_body = self.block(then_start, then_end);
        if else_range.is_some() {
            self.enclosing_ends.pop();
        }
        let mut arms = vec![(cond, then_body)];
        let mut els = None;
        let mut next = then_end.max(false_target);
        if let Some((s, e)) = else_range {
            let else_body = self.block(s, e);
            // A lone `if` in the else branch is an `elseif`.
            if else_body.len() == 1 {
                if let Stmt::If(inner_arms, inner_else) = &else_body[0] {
                    arms.extend(inner_arms.clone());
                    els = inner_else.clone();
                    self.out.push(Stmt::If(arms, els));
                    return e;
                }
            }
            els = Some(else_body);
            next = e;
        }
        self.out.push(Stmt::If(arms, els));
        next
    }

    /// Recognise a test that produces a value rather than branching, i.e. `and` / `or` in
    /// expression position. See the comment on the guard for why this is careful.
    fn try_value_condition(&mut self, pc: usize, end: usize) -> Option<usize> {
        let ins = self.ins(pc);
        let (target_reg, src) = match self.op(pc) {
            "TESTSET" => (ins.a() as usize, ins.b() as usize),
            // TEST is what TESTSET is rewritten to when source and destination coincide,
            // which makes it ambiguous with a plain `if`. Only read it as a value when the
            // range really does just compute into that register and something consumes it.
            "TEST" | "TEST_R1" => (ins.a() as usize, ins.a() as usize),
            _ => return None,
        };
        let t = self.jump_target(pc + 1);
        if t <= pc + 2 || t > end {
            return None;
        }
        let range = pc + 2..t;
        if range.clone().any(|i| self.is_statement_like(i)) {
            return None;
        }
        // The last instruction of the range must land in the same register.
        let last = t - 1;
        if self.writes_reg(last) != Some(target_reg) {
            return None;
        }
        if self.op(pc) != "TESTSET" {
            // For the rewritten TEST form, require evidence the value is consumed: either
            // the next instruction reads it, or a local's scope opens on it right there.
            let consumed = self.reads_reg(t, target_reg)
                || self
                    .local_at(target_reg, t)
                    .map(|li| self.p.locvars[li].startpc as usize == t)
                    .unwrap_or(false);
            if !consumed {
                return None;
            }
        }

        let lhs = self.reg(src, pc);
        let op = if self.ins(pc).c() == 0 { "and" } else { "or" };
        let outer = self.value_target.replace(target_reg);
        let stray = self.block(pc + 2, t);
        self.value_target = outer;
        if !stray.is_empty() {
            // Pure expressions produce no statements; if any appeared the shape was not
            // what it looked like, so keep them and say so.
            self.out.extend(stray);
            self.note(format!("`{op}` expression at pc {pc} contained statements"));
        }
        // Read the register directly: the built value matters here, not the name the
        // register carries.
        let rhs = self.regs.get(target_reg).and_then(|x| x.clone()).unwrap_or(Expr::Nil);
        let value = Expr::Binop(op, Box::new(lhs), Box::new(rhs));
        self.assign(target_reg, value, t);
        Some(t)
    }

    fn is_statement_like(&self, pc: usize) -> bool {
        match self.op(pc) {
            "SETGLOBAL" | "SETFIELD" | "SETFIELD_R1" | "SETTABLE" | "SETTABLE_S"
            | "SETTABLE_N" | "SETTABLE_BK" | "SETTABLE_S_BK" | "SETTABLE_N_BK" | "RETURN"
            | "SETUPVAL" | "SETUPVAL_R1" | "CLOSE" | "FORPREP" | "FORLOOP" | "TFORLOOP"
            | "TAILCALL" | "TAILCALL_I" | "TAILCALL_C" | "TAILCALL_M" | "TAILCALL_I_R1" => true,
            "CALL" | "CALL_I" | "CALL_C" | "CALL_M" | "CALL_I_R1" => self.ins(pc).c() == 1,
            "JMP" => self.jump_target(pc) <= pc,
            _ => false,
        }
    }

    fn writes_reg(&self, pc: usize) -> Option<usize> {
        match self.op(pc) {
            "" | "JMP" | "SETGLOBAL" | "SETFIELD" | "SETFIELD_R1" | "SETTABLE" | "SETTABLE_S"
            | "SETTABLE_N" | "SETTABLE_BK" | "SETTABLE_S_BK" | "SETTABLE_N_BK" | "RETURN"
            | "SETUPVAL" | "SETUPVAL_R1" | "CLOSE" | "SETLIST" => None,
            _ => Some(self.ins(pc).a() as usize),
        }
    }

    fn reads_reg(&self, pc: usize, r: usize) -> bool {
        let ins = self.ins(pc);
        let (a, b, c) = (ins.a() as usize, ins.b() as usize, ins.c() as usize);
        match self.op(pc) {
            "MOVE" | "GETFIELD" | "GETFIELD_R1" | "GETTABLE" | "GETTABLE_S" | "GETTABLE_N"
            | "SELF" | "UNM" | "NOT" | "NOT_R1" | "LEN" | "TESTSET" => b == r,
            "SETGLOBAL" | "TEST" | "TEST_R1" | "SETUPVAL" | "SETUPVAL_R1" => a == r,
            "SETFIELD" | "SETFIELD_R1" | "SETTABLE" | "SETTABLE_S" | "SETTABLE_N"
            | "SETTABLE_BK" | "SETTABLE_S_BK" | "SETTABLE_N_BK" => a == r || c == r,
            "CALL" | "CALL_I" | "CALL_C" | "CALL_M" | "CALL_I_R1" | "TAILCALL" | "TAILCALL_I"
            | "TAILCALL_C" | "TAILCALL_M" | "TAILCALL_I_R1" => a <= r && (b == 0 || r < a + b),
            "RETURN" => a <= r && (b == 0 || r < a + b - 1),
            "CONCAT" => b <= r && r <= c,
            "EQ" | "LT" | "LE" => b == r || c == r,
            _ => b == r || c == r,
        }
    }

    // ---- straight-line instructions ------------------------------------------------

    fn simple(&mut self, pc: usize) -> usize {
        let ins = self.ins(pc);
        let (a, b, c) = (ins.a() as usize, ins.b() as usize, ins.c() as usize);
        let name = self.op(pc);

        match name {
            "MOVE" => {
                let v = self.reg(b, pc);
                self.assign(a, v, pc);
            }
            "LOADK" => {
                let v = self.konst(ins.bx() as usize);
                self.assign(a, v, pc);
            }
            "LOADNIL" => {
                for r in a..=b.max(a) {
                    self.assign(r, Expr::Nil, pc);
                }
            }
            "LOADBOOL" => {
                self.assign(a, Expr::Bool(b != 0), pc);
                if c != 0 {
                    return pc + 2;
                }
            }
            "VARARG" => {
                self.assign(a, Expr::Vararg, pc);
                for r in a + 1..a + b.saturating_sub(1).max(1) {
                    self.set_reg(r, Expr::MultiRest);
                }
            }
            "GETGLOBAL" => {
                let n = self.const_name(ins.bx() as usize);
                self.assign(a, Expr::Global(n), pc);
            }
            "SETGLOBAL" => {
                let n = self.const_name(ins.bx() as usize);
                let v = self.reg(a, pc);
                self.out.push(Stmt::Assign(vec![Expr::Global(n)], vec![v]));
            }
            "GETUPVAL" => {
                let v = self.upvalue(b);
                self.assign(a, v, pc);
            }
            "SETUPVAL" | "SETUPVAL_R1" => {
                let target = self.upvalue(b);
                let v = self.reg(a, pc);
                self.out.push(Stmt::Assign(vec![target], vec![v]));
            }
            // Field and table reads all lower to R(A) := R(B)[key]; only the key differs.
            "GETFIELD" | "GETFIELD_R1" => {
                let t = self.reg(b, pc);
                let k = self.konst(c);
                let v = self.index(t, k);
                self.assign(a, v, pc);
            }
            "GETTABLE" | "GETTABLE_S" | "GETTABLE_N" => {
                let t = self.reg(b, pc);
                let k = self.rk(ins.c(), pc);
                let v = self.index(t, k);
                self.assign(a, v, pc);
            }
            // Writes lower to R(A)[key] := value, with the table-constructor case folded in.
            "SETFIELD" | "SETFIELD_R1" => {
                let k = self.konst(b);
                let v = self.rk(ins.c(), pc);
                self.set_field(a, k, v, pc);
            }
            "SETTABLE" | "SETTABLE_S" | "SETTABLE_N" => {
                let k = self.rk(ins.b(), pc);
                let v = self.rk(ins.c(), pc);
                self.set_field(a, k, v, pc);
            }
            "SETTABLE_BK" | "SETTABLE_S_BK" | "SETTABLE_N_BK" => {
                let k = self.konst(b);
                let v = self.rk(ins.c(), pc);
                self.set_field(a, k, v, pc);
            }
            "NEWTABLE" | "NEWSTRUCT" => {
                self.set_reg(a, Expr::Table { array: Vec::new(), hash: Vec::new() });
            }
            "SETLIST" => {
                let count = if b == 0 { self.top.saturating_sub(a + 1) } else { b };
                let mut items = Vec::new();
                for i in 1..=count {
                    items.push(self.reg(a + i, pc));
                }
                let base = if c == 0 { 0 } else { (c - 1) * 50 };
                match self.regs.get_mut(a) {
                    Some(Some(Expr::Table { array, .. })) if base == array.len() => {
                        array.extend(items);
                    }
                    _ => {
                        let table = self.reg(a, pc);
                        for (i, v) in items.into_iter().enumerate() {
                            let key = Expr::Number((base + i + 1) as f32);
                            let target = self.index(table.clone(), key);
                            self.out.push(Stmt::Assign(vec![target], vec![v]));
                        }
                    }
                }
                if c == 0 {
                    return pc + 2; // the real C rides in the next word
                }
            }
            "SELF" => {
                let obj = self.reg(b, pc);
                let k = self.rk(ins.c(), pc);
                self.set_reg(a + 1, obj.clone());
                let m = self.index(obj, k);
                self.set_reg(a, m);
                self.method_regs[a] = true;
            }
            "ADD" | "SUB" | "MUL" | "DIV" | "MOD" | "POW" | "ADD_BK" | "SUB_BK" | "MUL_BK"
            | "DIV_BK" | "MOD_BK" | "POW_BK" => {
                let lhs = if name.ends_with("_BK") { self.konst(b) } else { self.reg(b, pc) };
                let rhs = self.rk(ins.c(), pc);
                let op = match name.trim_end_matches("_BK") {
                    "ADD" => "+",
                    "SUB" => "-",
                    "MUL" => "*",
                    "DIV" => "/",
                    "MOD" => "%",
                    _ => "^",
                };
                let v = Expr::Binop(op, Box::new(lhs), Box::new(rhs));
                self.assign(a, v, pc);
            }
            "BOR" | "BXOR" | "BSHL" | "BSHR" => {
                // LuaPlus bitwise operators. They have no Lua 5.1 source form, so name the
                // operation rather than invent syntax. None occur in the shipped scripts.
                let lhs = self.reg(b, pc);
                let rhs = self.rk(ins.c(), pc);
                let f = Expr::Unknown(format!("__{}", name.to_lowercase()));
                let v = Expr::Call(Box::new(f), vec![lhs, rhs]);
                self.assign(a, v, pc);
            }
            "UNM" => {
                let v = self.reg(b, pc);
                let v = Expr::Unop("-", Box::new(v));
                self.assign(a, v, pc);
            }
            "NOT" | "NOT_R1" => {
                let v = self.reg(b, pc);
                let v = negate(v);
                self.assign(a, v, pc);
            }
            "LEN" => {
                let v = self.reg(b, pc);
                let v = Expr::Unop("#", Box::new(v));
                self.assign(a, v, pc);
            }
            "CONCAT" => {
                let mut parts = Vec::new();
                for r in b..=c {
                    parts.push(self.reg(r, pc));
                }
                self.assign(a, Expr::Concat(parts), pc);
            }
            "CLOSURE" => {
                let idx = ins.bx() as usize;
                let nups = self.p.protos.get(idx).map(|p| p.nups as usize).unwrap_or(0);
                let f = self.closure(idx);
                self.assign(a, f, pc);
                // The upvalue bindings ride as pseudo-instructions after CLOSURE.
                return pc + 1 + nups;
            }
            "CLOSE" => {}
            "CALL" | "CALL_I" | "CALL_C" | "CALL_M" | "CALL_I_R1" => return self.call(pc, false),
            "TAILCALL" | "TAILCALL_I" | "TAILCALL_C" | "TAILCALL_M" | "TAILCALL_I_R1" => {
                return self.call(pc, true)
            }
            "RETURN" => {
                let mut values = Vec::new();
                let n = if b == 0 { self.top.saturating_sub(a) } else { b.saturating_sub(1) };
                for r in a..a + n {
                    match self.regs.get(r).and_then(|x| x.clone()) {
                        Some(Expr::MultiRest) => {}
                        _ => values.push(self.reg(r, pc)),
                    }
                }
                self.out.push(Stmt::Return(values));
            }
            "FORLOOP" | "TFORLOOP" => {} // consumed by the loop handlers
            "DATA" | "OPCODE_MAX" => {}
            "" => self.note(format!("undecodable instruction at pc {pc}")),
            other => self.note(format!("unhandled opcode {other} at pc {pc}")),
        }
        pc + 1
    }

    fn const_name(&self, i: usize) -> String {
        match self.p.constants.get(i) {
            Some(Constant::Str(s)) => {
                let n = String::from_utf8_lossy(s).into_owned();
                if is_name(&n) {
                    n
                } else {
                    format!("_G[{}]", crate::ast::render(&[Stmt::Return(vec![Expr::Str(s.clone())])]).trim().trim_start_matches("return ").to_string())
                }
            }
            _ => format!("_k{i}"),
        }
    }

    fn set_field(&mut self, table_reg: usize, key: Expr, value: Expr, pc: usize) {
        // Fold into a table constructor while the register still holds an unnamed table.
        if self.local_name(table_reg, pc).is_none() {
            if let Some(Some(Expr::Table { hash, .. })) = self.regs.get_mut(table_reg) {
                hash.push((key, value));
                return;
            }
        }
        let t = self.reg(table_reg, pc);
        let target = self.index(t, key);
        self.out.push(Stmt::Assign(vec![target], vec![value]));
    }

    fn closure(&mut self, idx: usize) -> Expr {
        let Some(child) = self.p.protos.get(idx) else {
            return Expr::Unknown(format!("<missing function {idx}>"));
        };
        let mut d = Decompiler::new(child);
        let body = d.function_body();
        let params = d.params();
        for n in d.notes {
            self.notes.push(n);
        }
        Expr::Function(Box::new(FuncBody {
            params,
            is_vararg: child.is_vararg & 2 != 0,
            body,
        }))
    }

    fn call(&mut self, pc: usize, tail: bool) -> usize {
        let ins = self.ins(pc);
        let (a, b, c) = (ins.a() as usize, ins.b() as usize, ins.c() as usize);
        let nargs = if b == 0 { self.top.saturating_sub(a + 1) } else { b - 1 };
        let mut args = Vec::new();
        for r in a + 1..a + 1 + nargs {
            match self.regs.get(r).and_then(|x| x.clone()) {
                Some(Expr::MultiRest) => {}
                _ => args.push(self.reg(r, pc)),
            }
        }

        // A SELF put the receiver in A+1 and the method in A, which is an `obj:method(...)`
        // call with the receiver duplicated. It is not necessarily the previous
        // instruction, since the arguments are built in between, so the register carries
        // the mark until something overwrites it.
        let func = self.reg(a, pc);
        let expr = match (&func, self.method_regs.get(a).copied().unwrap_or(false)) {
            (Expr::Index(obj, key), true) => match &**key {
                Expr::Str(s) if is_name(&String::from_utf8_lossy(s)) => {
                    let name = String::from_utf8_lossy(s).into_owned();
                    if !args.is_empty() {
                        args.remove(0);
                    }
                    Expr::Method(obj.clone(), name, args)
                }
                _ => Expr::Call(Box::new(func.clone()), args),
            },
            _ => Expr::Call(Box::new(func.clone()), args),
        };

        if tail {
            self.out.push(Stmt::Return(vec![expr]));
            // A tail call is always followed by a RETURN that the source did not write.
            return if self.op(pc + 1) == "RETURN" { pc + 2 } else { pc + 1 };
        }
        if c == 1 {
            self.out.push(Stmt::Call(expr));
            self.top = a;
            return pc + 1;
        }
        self.set_reg(a, expr);
        if c == 0 {
            self.top = a + 1;
        } else {
            for r in a + 1..a + c - 1 {
                self.set_reg(r, Expr::MultiRest);
            }
            self.top = a + c - 1;
        }
        // Multiple results landing in registers that are not about to become locals still
        // need somewhere to go, so emit the assignment now.
        let extra: Vec<usize> = (a + 1..a.saturating_add(c.saturating_sub(1)))
            .filter(|&r| {
                self.local_at(r, pc + 1)
                    .map(|li| self.p.locvars[li].startpc as usize != pc + 1)
                    .unwrap_or(false)
            })
            .collect();
        if !extra.is_empty() {
            let mut targets = vec![self.reg(a, pc)];
            for &r in &extra {
                targets.push(self.reg(r, pc + 1));
            }
            let value = self.regs[a].clone().unwrap_or(Expr::Nil);
            targets[0] = self.reg(a, pc + 1);
            self.out.push(Stmt::Assign(targets, vec![value]));
        }
        pc + 1
    }
}

/// Lua 5.1 requires `return` and `break` to be the last statement in their block. The
/// compiler emits code after them freely, and source that does this writes
/// `do return x end`, so restore that form rather than produce something that will not
/// parse.
fn seal_terminators(stmts: &mut [Stmt]) {
    let n = stmts.len();
    for (i, s) in stmts.iter_mut().enumerate() {
        if i + 1 == n {
            continue;
        }
        if matches!(s, Stmt::Return(_) | Stmt::Break) {
            let old = std::mem::replace(s, Stmt::Break);
            *s = Stmt::Do(vec![old]);
        }
    }
}

fn negate(e: Expr) -> Expr {
    match e {
        Expr::Binop("==", a, b) => Expr::Binop("~=", a, b),
        Expr::Binop("~=", a, b) => Expr::Binop("==", a, b),
        Expr::Binop("<", a, b) => Expr::Binop(">=", a, b),
        Expr::Binop(">=", a, b) => Expr::Binop("<", a, b),
        Expr::Binop("<=", a, b) => Expr::Binop(">", a, b),
        Expr::Binop(">", a, b) => Expr::Binop("<=", a, b),
        Expr::Unop("not", inner) => *inner,
        Expr::Bool(b) => Expr::Bool(!b),
        other => Expr::Unop("not", Box::new(other)),
    }
}
