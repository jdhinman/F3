//! F3 Bridge: a d3d9.dll proxy for Fable III (32-bit).
//!
//! Three jobs, in the order they run:
//!   1. Proxy   - forward Direct3DCreate9 to the real system d3d9 so the game boots.
//!   2. Overlay - hook IDirect3DDevice9::EndScene and draw a menu with ID3DXFont.
//!   3. Bridge  - on selection, write a small Lua file that the in-game script picks up
//!                via RunScript. The DLL never touches game state itself; all mutation
//!                stays in Lua where it is live-editable and uses proven calls.
//!
//! Why a file and not a direct call into the VM: Fable III's Lua is KoreVM, a custom
//! implementation with none of the standard luaL_ entry points, so registering a native
//! function is not available to us. RunScript re-reads from disk (that is the whole live
//! edit loop), which makes a file the cheapest reliable channel.
//!
//! Fable3.exe imports exactly one symbol from d3d9.dll (Direct3DCreate9), so only that
//! one must be perfect; the D3DPERF_* forwards exist for tools that poke them.

#![allow(non_snake_case)]

use std::ffi::{c_void, CString};
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicIsize, AtomicU32, Ordering};

type HMODULE = *mut c_void;
type HRESULT = i32;
type DWORD = u32;
type BOOL = i32;

#[link(name = "kernel32")]
extern "system" {
    fn LoadLibraryA(name: *const i8) -> HMODULE;
    fn GetModuleHandleA(name: *const i8) -> HMODULE;
    fn GetProcAddress(module: HMODULE, name: *const i8) -> *mut c_void;
    fn GetSystemDirectoryA(buf: *mut u8, size: u32) -> u32;
    fn GetModuleFileNameA(module: HMODULE, buf: *mut u8, size: u32) -> u32;
    fn VirtualProtect(addr: *mut c_void, size: usize, new: u32, old: *mut u32) -> BOOL;
    fn CreateFileA(
        name: *const i8,
        access: u32,
        share: u32,
        sa: *mut c_void,
        disp: u32,
        flags: u32,
        template: HMODULE,
    ) -> HMODULE;
    fn WriteFile(h: HMODULE, buf: *const u8, len: u32, written: *mut u32, ov: *mut c_void) -> BOOL;
    fn CloseHandle(h: HMODULE) -> BOOL;
    fn MoveFileExA(from: *const i8, to: *const i8, flags: u32) -> BOOL;
}

#[link(name = "user32")]
extern "system" {
    fn GetAsyncKeyState(vk: i32) -> i16;
    fn SetWindowsHookExA(
        id: i32,
        proc_: unsafe extern "system" fn(i32, usize, isize) -> isize,
        module: HMODULE,
        thread: u32,
    ) -> HMODULE;
    fn CallNextHookEx(hook: HMODULE, code: i32, w: usize, l: isize) -> isize;
    fn PeekMessageA(msg: *mut u8, hwnd: HMODULE, min: u32, max: u32, remove: u32) -> BOOL;
    fn TranslateMessage(msg: *const u8) -> BOOL;
    fn DispatchMessageA(msg: *const u8) -> isize;
}

// Low-level keyboard hook. Fable III takes the keyboard through DirectInput8 in exclusive
// mode, which is exactly the case where polling can come back empty; a WH_KEYBOARD_LL hook
// sees keys ahead of DirectInput, so it works when GetAsyncKeyState does not.
const WH_KEYBOARD_LL: i32 = 13;
const HC_ACTION: i32 = 0;
const WM_KEYDOWN: usize = 0x0100;
const WM_SYSKEYDOWN: usize = 0x0104;
const PM_REMOVE: u32 = 1;

static SELF_MODULE: AtomicIsize = AtomicIsize::new(0);
static HOOK_KEYS: AtomicU32 = AtomicU32::new(0);

/// Map a virtual key to our action id, or 0 if we do not care about it.
fn action_for(vk: u32) -> u32 {
    match vk as i32 {
        VK_F1 => 1,
        VK_UP => 2,
        VK_DOWN => 3,
        VK_RETURN => 4,
        _ => 0,
    }
}

unsafe extern "system" fn ll_keyboard_proc(code: i32, wparam: usize, lparam: isize) -> isize {
    if code == HC_ACTION && (wparam == WM_KEYDOWN || wparam == WM_SYSKEYDOWN) {
        // KBDLLHOOKSTRUCT starts with DWORD vkCode.
        let vk = *(lparam as *const u32);
        let action = action_for(vk);
        if action != 0 {
            let n = HOOK_KEYS.fetch_add(1, Ordering::AcqRel);
            if n < 8 {
                log(&format!("LL hook: vk={} -> action {}", vk, action));
            }
            write_key(action);
        }
    }
    CallNextHookEx(ptr::null_mut(), code, wparam, lparam)
}

extern "system" {
    fn GetTickCount() -> u32;
    fn Sleep(ms: u32);
    fn CreateThread(
        attrs: *mut c_void,
        stack: usize,
        start: unsafe extern "system" fn(*mut c_void) -> u32,
        param: *mut c_void,
        flags: u32,
        id: *mut u32,
    ) -> HMODULE;
}

/// Append one line to <game dir>\f3bridge.log. Cheap and only called on state changes,
/// so per-frame cost is nil. The file is the only window we have into a running hook.
/// Opening with FILE_APPEND_DATA (0x0004) appends without any seek call.
unsafe fn log(msg: &str) {
    let mut buf = [0u8; 640];
    let n = GetModuleFileNameA(ptr::null_mut(), buf.as_mut_ptr(), 600) as usize;
    let mut p = Vec::from(&buf[..n]);
    while let Some(&c) = p.last() {
        if c == b'\\' {
            break;
        }
        p.pop();
    }
    p.extend_from_slice(b"f3bridge.log\0");
    let h = CreateFileA(
        p.as_ptr() as *const i8,
        FILE_APPEND,
        0,
        ptr::null_mut(),
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        ptr::null_mut(),
    );
    if h as isize == INVALID_HANDLE {
        return;
    }
    let line = format!("[{}] {}\r\n", GetTickCount(), msg);
    let mut w = 0u32;
    WriteFile(h, line.as_ptr(), line.len() as u32, &mut w, ptr::null_mut());
    CloseHandle(h);
}

const OPEN_ALWAYS: u32 = 4;
const FILE_APPEND: u32 = 4;
const PAGE_READWRITE: u32 = 0x04;
const GENERIC_WRITE: u32 = 0x4000_0000;
const CREATE_ALWAYS: u32 = 2;
const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
const INVALID_HANDLE: isize = -1;
const MOVEFILE_REPLACE_EXISTING: u32 = 0x1;

// Virtual keys. F1 toggles; arrows move; Enter activates.
const VK_RETURN: i32 = 0x0D;
const VK_UP: i32 = 0x26;
const VK_DOWN: i32 = 0x28;
const VK_F1: i32 = 0x70;

// COM vtable slots we hook or call.
const IDIRECT3D9_CREATEDEVICE: usize = 16;
const DEV_RESET: usize = 16;
const DEV_PRESENT: usize = 17;
const DEV_ENDSCENE: usize = 42;
const DEV_CLEAR: usize = 43;
const DEV_CREATESTATEBLOCK: usize = 59;
const SB_CAPTURE: usize = 4;
const SB_APPLY: usize = 5;
const D3DSBT_ALL: u32 = 1;
const FONT_DRAWTEXTA: usize = 14;
const FONT_ONLOSTDEVICE: usize = 16;
const FONT_ONRESETDEVICE: usize = 17;

const D3DCLEAR_TARGET: u32 = 0x1;
const DT_NOCLIP: u32 = 0x100;

static REAL_D3D9: AtomicIsize = AtomicIsize::new(0);
static ORIG_CREATEDEVICE: AtomicIsize = AtomicIsize::new(0);
static ORIG_ENDSCENE: AtomicIsize = AtomicIsize::new(0);
static ORIG_PRESENT: AtomicIsize = AtomicIsize::new(0);
static ORIG_RESET: AtomicIsize = AtomicIsize::new(0);
static ENDSCENE_COUNT: AtomicU32 = AtomicU32::new(0);
static PRESENT_COUNT: AtomicU32 = AtomicU32::new(0);
static FONT: AtomicIsize = AtomicIsize::new(0);
static FONT_BIG: AtomicIsize = AtomicIsize::new(0);
static MENU_OPEN: AtomicBool = AtomicBool::new(false);
static SELECTED: AtomicU32 = AtomicU32::new(0);
static CMD_ID: AtomicU32 = AtomicU32::new(0);
static DRAW_LOGS: AtomicU32 = AtomicU32::new(0);
static STATE_BLOCK: AtomicIsize = AtomicIsize::new(0);
static STARTED: AtomicBool = AtomicBool::new(false);
static STATUS: AtomicU32 = AtomicU32::new(0);

const ITEMS: &[(&str, u32)] = &[
    ("Gold  +50,000", 1),
    ("Refill health", 2),
    ("Guild seals  +50", 3),
    ("Evolve held weapon", 4),
    ("Toggle HUD inspector", 5),
];

/// Load the real d3d9 from the system directory. Loading by bare name would find us.
unsafe fn real_d3d9() -> HMODULE {
    let cached = REAL_D3D9.load(Ordering::Acquire);
    if cached != 0 {
        return cached as HMODULE;
    }
    let mut buf = [0u8; 320];
    let n = GetSystemDirectoryA(buf.as_mut_ptr(), 260) as usize;
    let mut path = Vec::from(&buf[..n]);
    path.extend_from_slice(b"\\d3d9.dll\0");
    let h = LoadLibraryA(path.as_ptr() as *const i8);
    REAL_D3D9.store(h as isize, Ordering::Release);
    h
}

unsafe fn real_proc(name: &str) -> *mut c_void {
    let c = CString::new(name).unwrap();
    GetProcAddress(real_d3d9(), c.as_ptr())
}

/// Swap one vtable entry, returning the original. The vtable lives in read-only memory,
/// so it needs VirtualProtect around the write.
unsafe fn hook_vtable(obj: *mut c_void, index: usize, hook: *mut c_void) -> *mut c_void {
    if obj.is_null() {
        return ptr::null_mut();
    }
    let vtable = *(obj as *mut *mut *mut c_void);
    let slot = vtable.add(index);
    let mut old_prot = 0u32;
    if VirtualProtect(slot as *mut c_void, 4, PAGE_READWRITE, &mut old_prot) == 0 {
        return ptr::null_mut();
    }
    let original = *slot;
    *slot = hook;
    VirtualProtect(slot as *mut c_void, 4, old_prot, &mut old_prot);
    original
}

/// <game dir>\data\scripts\MyMod\<name>, derived from the running exe so nothing is
/// hardcoded to one install.
unsafe fn game_path(name: &str) -> Vec<u8> {
    let mut buf = [0u8; 640];
    let n = GetModuleFileNameA(ptr::null_mut(), buf.as_mut_ptr(), 600) as usize;
    let mut p = Vec::from(&buf[..n]);
    while let Some(&c) = p.last() {
        if c == b'\\' {
            break;
        }
        p.pop();
    }
    p.extend_from_slice(b"data\\scripts\\MyMod\\");
    p.extend_from_slice(name.as_bytes());
    p.push(0);
    p
}

/// Write the command file the Lua worker runs. Written to a temp name then moved, so the
/// worker can never RunScript a half-written file.
unsafe fn write_command(action: u32) {
    let id = CMD_ID.fetch_add(1, Ordering::AcqRel) + 1;
    let body = format!("F3CMD = {{ id = {}, action = {} }}\n", id, action);
    let tmp = game_path("F3Bridge.tmp");
    let dst = game_path("F3Bridge.lua");
    let h = CreateFileA(
        tmp.as_ptr() as *const i8,
        GENERIC_WRITE,
        0,
        ptr::null_mut(),
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        ptr::null_mut(),
    );
    if h as isize == INVALID_HANDLE {
        STATUS.store(2, Ordering::Release);
        return;
    }
    let mut written = 0u32;
    WriteFile(h, body.as_ptr(), body.len() as u32, &mut written, ptr::null_mut());
    CloseHandle(h);
    if MoveFileExA(
        tmp.as_ptr() as *const i8,
        dst.as_ptr() as *const i8,
        MOVEFILE_REPLACE_EXISTING,
    ) == 0
    {
        STATUS.store(2, Ordering::Release);
    } else {
        STATUS.store(1, Ordering::Release);
    }
}

/// Ensure the bridge file exists and is a harmless no-op. RunScript on a missing file
/// would raise a Lua error, and there is no pcall in this environment to catch it.
unsafe fn seed_command_file() {
    let dst = game_path("F3Bridge.lua");
    let h = CreateFileA(
        dst.as_ptr() as *const i8,
        GENERIC_WRITE,
        0,
        ptr::null_mut(),
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        ptr::null_mut(),
    );
    if h as isize != INVALID_HANDLE {
        let body = b"F3CMD = { id = 0, action = 0 }\n";
        let mut w = 0u32;
        WriteFile(h, body.as_ptr(), body.len() as u32, &mut w, ptr::null_mut());
        CloseHandle(h);
    }
}

type FnClear = unsafe extern "system" fn(*mut c_void, u32, *const i32, u32, u32, f32, u32) -> HRESULT;
type FnDrawText =
    unsafe extern "system" fn(*mut c_void, *mut c_void, *const i8, i32, *mut i32, u32, u32) -> i32;
type FnFontDevice = unsafe extern "system" fn(*mut c_void) -> HRESULT;
type FnCreateFont = unsafe extern "system" fn(
    *mut c_void, i32, u32, u32, u32, BOOL, u32, u32, u32, u32, *const i8, *mut *mut c_void,
) -> HRESULT;

unsafe fn make_font(device: *mut c_void, height: i32, weight: u32) -> *mut c_void {
    // d3dx9_42 is already loaded (the game imports it), so this is a handle lookup.
    let mut h = GetModuleHandleA(b"d3dx9_42.dll\0".as_ptr() as *const i8);
    if h.is_null() {
        h = LoadLibraryA(b"d3dx9_42.dll\0".as_ptr() as *const i8);
    }
    if h.is_null() {
        return ptr::null_mut();
    }
    let p = GetProcAddress(h, b"D3DXCreateFontA\0".as_ptr() as *const i8);
    if p.is_null() {
        return ptr::null_mut();
    }
    let create: FnCreateFont = std::mem::transmute(p);
    let mut font: *mut c_void = ptr::null_mut();
    // DEFAULT_CHARSET=1, OUT_DEFAULT_PRECIS=0, CLEARTYPE_QUALITY=5, DEFAULT_PITCH|FF_DONTCARE=0
    let face = b"Tahoma\0";
    if create(device, height, 0, weight, 1, 0, 1, 0, 5, 0, face.as_ptr() as *const i8, &mut font) < 0
    {
        return ptr::null_mut();
    }
    font
}

unsafe fn draw_text(font: *mut c_void, text: &str, x: i32, y: i32, color: u32) {
    if font.is_null() {
        return;
    }
    let vt = *(font as *mut *mut *mut c_void);
    let f: FnDrawText = std::mem::transmute(*vt.add(FONT_DRAWTEXTA));
    let c = match CString::new(text) {
        Ok(c) => c,
        Err(_) => return,
    };
    let mut rect = [x, y, x + 1000, y + 40];
    f(font, ptr::null_mut(), c.as_ptr(), -1, rect.as_mut_ptr(), DT_NOCLIP, color);
}

/// Solid rectangle without vertex buffers: Clear with a sub-rect only touches that rect.
unsafe fn fill_rect(device: *mut c_void, x1: i32, y1: i32, x2: i32, y2: i32, color: u32) {
    let vt = *(device as *mut *mut *mut c_void);
    let clear: FnClear = std::mem::transmute(*vt.add(DEV_CLEAR));
    let rect = [x1, y1, x2, y2];
    clear(device, 1, rect.as_ptr(), D3DCLEAR_TARGET, color, 1.0, 0);
}

/// Rising-edge key test; one press yields one action.
fn key_pressed(vk: i32, prev: &mut bool) -> bool {
    let down = unsafe { (GetAsyncKeyState(vk) as u16 & 0x8000) != 0 };
    let fired = down && !*prev;
    *prev = down;
    fired
}

static mut PREV_F1: bool = false;
static mut PREV_UP: bool = false;
static mut PREV_DOWN: bool = false;
static mut PREV_ENTER: bool = false;

/// Input, polled once per frame from the Present hook. This is the one input path proven
/// to work in this game: the very first build detected F1 here. It needs no extra thread
/// (which hung startup) and no system-wide hook (which hung the whole game).
///
/// All four keys are reported straight to Lua as (seq, key) events; Lua owns the menu
/// state and drawing. Nothing is drawn from here, which is what keeps the hook alive -
/// drawing corrupted device state and the render loop stopped calling us.
unsafe fn process_input() {
    let keys = [
        (VK_F1, 1u32, ptr::addr_of_mut!(PREV_F1)),
        (VK_UP, 2, ptr::addr_of_mut!(PREV_UP)),
        (VK_DOWN, 3, ptr::addr_of_mut!(PREV_DOWN)),
        (VK_RETURN, 4, ptr::addr_of_mut!(PREV_ENTER)),
    ];
    for (vk, action, prev) in keys {
        if key_pressed(vk, &mut *prev) {
            let n = HOOK_KEYS.fetch_add(1, Ordering::AcqRel);
            if n < 12 {
                log(&format!("key vk={} -> action {}", vk, action));
            }
            write_key(action);
        }
    }
}

unsafe fn draw_overlay(device: *mut c_void) {
    // D3D drawing is disabled. Fable III's render loop keeps running normally while our
    // hooked EndScene stops being reached after the first draw, so the overlay is not a
    // fight worth having; the menu is drawn from Lua with GUI.SetCounter instead. The
    // hooks stay installed purely as diagnostics.
    if true {
        return;
    }
    if !MENU_OPEN.load(Ordering::Acquire) {
        return;
    }

    if FONT.load(Ordering::Acquire) == 0 {
        let f = make_font(device, 18, 400);
        let fb = make_font(device, 24, 700);
        FONT.store(f as isize, Ordering::Release);
        FONT_BIG.store(fb as isize, Ordering::Release);
        log(&format!("font create: small={} big={}", !f.is_null(), !fb.is_null()));
    }
    let font = FONT.load(Ordering::Acquire) as *mut c_void;
    let font_big = FONT_BIG.load(Ordering::Acquire) as *mut c_void;

    // Stage logging for the first few draws only: whichever line is missing from the log
    // is the call that faults. Cheap, and it costs nothing once DRAW_LOGS is exhausted.
    let n_draw = DRAW_LOGS.fetch_add(1, Ordering::AcqRel);
    let verbose = n_draw < 3;
    if verbose {
        log("draw: begin");
    }

    // Save every render state before we touch anything, and restore it afterwards.
    // Without this, ID3DXFont::DrawText and Clear leave the device in a state the game
    // does not expect, and its render loop stops issuing frames entirely - which is
    // exactly what the first build did (one successful draw, then no more EndScene).
    let vt_dev = *(device as *mut *mut *mut c_void);
    if STATE_BLOCK.load(Ordering::Acquire) == 0 {
        let create: unsafe extern "system" fn(*mut c_void, u32, *mut *mut c_void) -> HRESULT =
            std::mem::transmute(*vt_dev.add(DEV_CREATESTATEBLOCK));
        let mut block: *mut c_void = ptr::null_mut();
        let hr = create(device, D3DSBT_ALL, &mut block);
        STATE_BLOCK.store(block as isize, Ordering::Release);
        log(&format!("state block create hr={:#x} ok={}", hr, !block.is_null()));
    }
    let block = STATE_BLOCK.load(Ordering::Acquire) as *mut c_void;
    if !block.is_null() {
        let vt_sb = *(block as *mut *mut *mut c_void);
        let capture: unsafe extern "system" fn(*mut c_void) -> HRESULT =
            std::mem::transmute(*vt_sb.add(SB_CAPTURE));
        capture(block);
    }

    let (x, y, w) = (60i32, 120i32, 340i32);
    let rows = ITEMS.len() as i32;
    let h = 78 + rows * 26;
    fill_rect(device, x, y, x + w, y + h, 0xD0_10_10_14);
    if verbose {
        log("draw: fill_rect ok");
    }

    draw_text(font_big, "F3MOD", x + 14, y + 5, 0xFF_F0_D8_A0);
    if verbose {
        log("draw: draw_text ok");
    }

    let sel = SELECTED.load(Ordering::Acquire) as usize;
    for (i, (label, _)) in ITEMS.iter().enumerate() {
        let ry = y + 44 + i as i32 * 26;
        if i == sel {
            draw_text(font, ">", x + 14, ry, 0xFF_FF_D8_70);
        }
        let color = if i == sel { 0xFF_FF_FF_FF } else { 0xFF_B0_B0_B8 };
        draw_text(font, label, x + 34, ry, color);
    }
    let foot = match STATUS.load(Ordering::Acquire) {
        1 => "sent - applies within ~1s",
        2 => "WRITE FAILED - check folder perms",
        _ => "F1 close   arrows move   Enter use",
    };
    draw_text(font, foot, x + 14, y + h - 26, 0xFF_88_90_A0);

    if !block.is_null() {
        let vt_sb = *(block as *mut *mut *mut c_void);
        let apply: unsafe extern "system" fn(*mut c_void) -> HRESULT =
            std::mem::transmute(*vt_sb.add(SB_APPLY));
        apply(block);
    }
    if verbose {
        log("draw: end + state restored");
    }
    // Prove the overlay is drawing every frame, not just once.
    if n_draw == 200 {
        log("draw: still drawing after 200 frames (overlay is stable)");
    }
}

unsafe extern "system" fn hooked_endscene(device: *mut c_void) -> HRESULT {
    let n = ENDSCENE_COUNT.fetch_add(1, Ordering::AcqRel);
    if n == 0 {
        log("endscene hook firing");
    }
    draw_overlay(device);
    let orig: unsafe extern "system" fn(*mut c_void) -> HRESULT =
        std::mem::transmute(ORIG_ENDSCENE.load(Ordering::Acquire));
    orig(device)
}

/// Present runs once per frame (unlike EndScene, which the game calls per render pass),
/// so all input is processed here for a stable, one-action-per-press response.
unsafe extern "system" fn hooked_present(
    device: *mut c_void,
    src: *const c_void,
    dst: *const c_void,
    hwnd: *mut c_void,
    dirty: *const c_void,
) -> HRESULT {
    let n = PRESENT_COUNT.fetch_add(1, Ordering::AcqRel);
    if n == 0 {
        log("present hook firing");
    }
    // Heartbeat. If this stops after the menu opens, the draw path is aborting the frame
    // before Present is reached, which also explains input dying.
    if n % 300 == 0 && n > 0 {
        log(&format!(
            "heartbeat: present={} endscene={} menu_open={}",
            n,
            ENDSCENE_COUNT.load(Ordering::Acquire),
            MENU_OPEN.load(Ordering::Acquire)
        ));
    }
    // Log the endscene:present ratio once, after a second or so of frames, to confirm the
    // multiple-endscene-per-frame theory that caused the flash.
    if n == 120 {
        let es = ENDSCENE_COUNT.load(Ordering::Acquire);
        log(&format!("after 120 presents: {} endscene calls (~{} per frame)", es, es / 120));
    }
    process_input();
    let orig: unsafe extern "system" fn(
        *mut c_void, *const c_void, *const c_void, *mut c_void, *const c_void,
    ) -> HRESULT = std::mem::transmute(ORIG_PRESENT.load(Ordering::Acquire));
    orig(device, src, dst, hwnd, dirty)
}

unsafe extern "system" fn hooked_reset(device: *mut c_void, params: *mut c_void) -> HRESULT {
    // Fonts hold device resources; they must be released before Reset and restored after.
    for slot in [&FONT, &FONT_BIG] {
        let f = slot.load(Ordering::Acquire) as *mut c_void;
        if !f.is_null() {
            let vt = *(f as *mut *mut *mut c_void);
            let lost: FnFontDevice = std::mem::transmute(*vt.add(FONT_ONLOSTDEVICE));
            lost(f);
        }
    }
    let orig: unsafe extern "system" fn(*mut c_void, *mut c_void) -> HRESULT =
        std::mem::transmute(ORIG_RESET.load(Ordering::Acquire));
    let hr = orig(device, params);
    for slot in [&FONT, &FONT_BIG] {
        let f = slot.load(Ordering::Acquire) as *mut c_void;
        if !f.is_null() {
            let vt = *(f as *mut *mut *mut c_void);
            let reset: FnFontDevice = std::mem::transmute(*vt.add(FONT_ONRESETDEVICE));
            reset(f);
        }
    }
    hr
}

unsafe extern "system" fn hooked_createdevice(
    this: *mut c_void,
    adapter: u32,
    dev_type: u32,
    focus: *mut c_void,
    flags: u32,
    params: *mut c_void,
    out_device: *mut *mut c_void,
) -> HRESULT {
    let orig: unsafe extern "system" fn(
        *mut c_void, u32, u32, *mut c_void, u32, *mut c_void, *mut *mut c_void,
    ) -> HRESULT = std::mem::transmute(ORIG_CREATEDEVICE.load(Ordering::Acquire));
    let hr = orig(this, adapter, dev_type, focus, flags, params, out_device);
    log("createdevice returned");
    if hr >= 0 && !out_device.is_null() && !(*out_device).is_null() {
        let dev = *out_device;
        if ORIG_ENDSCENE.load(Ordering::Acquire) == 0 {
            let e = hook_vtable(dev, DEV_ENDSCENE, hooked_endscene as *mut c_void);
            ORIG_ENDSCENE.store(e as isize, Ordering::Release);
            let pr = hook_vtable(dev, DEV_PRESENT, hooked_present as *mut c_void);
            ORIG_PRESENT.store(pr as isize, Ordering::Release);
            let r = hook_vtable(dev, DEV_RESET, hooked_reset as *mut c_void);
            ORIG_RESET.store(r as isize, Ordering::Release);
            seed_command_file();
            log("device hooks installed (endscene+present+reset)");
        }
    } else {
        log("createdevice: no device returned");
    }
    hr
}

#[no_mangle]
pub unsafe extern "system" fn Direct3DCreate9(sdk_version: u32) -> *mut c_void {
    let p = real_proc("Direct3DCreate9");
    if p.is_null() {
        return ptr::null_mut();
    }
    let f: unsafe extern "system" fn(u32) -> *mut c_void = std::mem::transmute(p);
    let first = !STARTED.swap(true, Ordering::AcqRel);
    if first {
        log("proxy: calling real Direct3DCreate9");
    }
    // Forward to the real d3d9 first and untouched: whatever the game needs to boot must
    // happen exactly as normal.
    let d3d = f(sdk_version);
    if first {
        log(&format!("proxy: real returned {}", if d3d.is_null() { "NULL" } else { "ok" }));
        seed_command_file();
        log("proxy: bridge file seeded");
    }
    // Hook CreateDevice so we can reach Present. NO extra thread: spawning one wedged
    // startup (its DLL_THREAD_ATTACH runs through every loaded DLL, DFA.dll included, and
    // the game never got past its first Direct3DCreate9). Input is polled from the Present
    // hook instead, which is already proven to fire for thousands of frames.
    if !d3d.is_null() && ORIG_CREATEDEVICE.load(Ordering::Acquire) == 0 {
        let orig = hook_vtable(d3d, IDIRECT3D9_CREATEDEVICE, hooked_createdevice as *mut c_void);
        ORIG_CREATEDEVICE.store(orig as isize, Ordering::Release);
        log("proxy: CreateDevice hooked");
    }
    d3d
}

// ---------------------------------------------------------------------------------------
// dinput8 host. The same one-import situation as d3d9 (Fable3.exe imports only
// DirectInput8Create), and it leaves d3d9.dll free for DXVK, which ships as d3d9.dll and
// would otherwise collide. Timeslip's 2011 save exporter proved this host works.
//
// Polling point: IDirectInputDevice8::GetDeviceState, which the game calls every frame -
// the same role Present plays in the d3d9 host. No extra thread (that hangs startup) and no
// system-wide hook (that stops the game launching).
// ---------------------------------------------------------------------------------------

const DI8_CREATEDEVICE: usize = 3;
const DI8DEV_GETDEVICESTATE: usize = 9;

static REAL_DINPUT8: AtomicIsize = AtomicIsize::new(0);
static ORIG_DI_CREATEDEVICE: AtomicIsize = AtomicIsize::new(0);
static ORIG_GETDEVICESTATE: AtomicIsize = AtomicIsize::new(0);
static DI_POLLS: AtomicU32 = AtomicU32::new(0);

unsafe fn real_dinput8() -> HMODULE {
    let cached = REAL_DINPUT8.load(Ordering::Acquire);
    if cached != 0 {
        return cached as HMODULE;
    }
    let mut buf = [0u8; 320];
    let n = GetSystemDirectoryA(buf.as_mut_ptr(), 260) as usize;
    let mut path = Vec::from(&buf[..n]);
    path.extend_from_slice(b"\\dinput8.dll\0");
    let h = LoadLibraryA(path.as_ptr() as *const i8);
    REAL_DINPUT8.store(h as isize, Ordering::Release);
    h
}

unsafe extern "system" fn hooked_getdevicestate(
    dev: *mut c_void,
    cb: u32,
    data: *mut c_void,
) -> HRESULT {
    let n = DI_POLLS.fetch_add(1, Ordering::AcqRel);
    if n == 0 {
        log("dinput: GetDeviceState hook firing");
    }
    process_input();
    let orig: unsafe extern "system" fn(*mut c_void, u32, *mut c_void) -> HRESULT =
        std::mem::transmute(ORIG_GETDEVICESTATE.load(Ordering::Acquire));
    orig(dev, cb, data)
}

unsafe extern "system" fn hooked_di_createdevice(
    this: *mut c_void,
    guid: *const c_void,
    out_dev: *mut *mut c_void,
    outer: *mut c_void,
) -> HRESULT {
    let orig: unsafe extern "system" fn(
        *mut c_void, *const c_void, *mut *mut c_void, *mut c_void,
    ) -> HRESULT = std::mem::transmute(ORIG_DI_CREATEDEVICE.load(Ordering::Acquire));
    let hr = orig(this, guid, out_dev, outer);
    if hr >= 0 && !out_dev.is_null() && !(*out_dev).is_null() {
        if ORIG_GETDEVICESTATE.load(Ordering::Acquire) == 0 {
            let g = hook_vtable(*out_dev, DI8DEV_GETDEVICESTATE,
                hooked_getdevicestate as *mut c_void);
            ORIG_GETDEVICESTATE.store(g as isize, Ordering::Release);
            log("dinput: GetDeviceState hooked");
        }
    }
    hr
}

#[no_mangle]
pub unsafe extern "system" fn DirectInput8Create(
    hinst: *mut c_void,
    version: u32,
    riid: *const c_void,
    out: *mut *mut c_void,
    outer: *mut c_void,
) -> HRESULT {
    let c = CString::new("DirectInput8Create").unwrap();
    let p = GetProcAddress(real_dinput8(), c.as_ptr());
    if p.is_null() {
        return -1;
    }
    let first = !STARTED.swap(true, Ordering::AcqRel);
    if first {
        log("dinput proxy: calling real DirectInput8Create");
    }
    let f: unsafe extern "system" fn(
        *mut c_void, u32, *const c_void, *mut *mut c_void, *mut c_void,
    ) -> HRESULT = std::mem::transmute(p);
    let hr = f(hinst, version, riid, out, outer);
    if first {
        seed_command_file();
        log("dinput proxy: bridge file seeded");
    }
    if hr >= 0 && !out.is_null() && !(*out).is_null()
        && ORIG_DI_CREATEDEVICE.load(Ordering::Acquire) == 0
    {
        let o = hook_vtable(*out, DI8_CREATEDEVICE, hooked_di_createdevice as *mut c_void);
        ORIG_DI_CREATEDEVICE.store(o as isize, Ordering::Release);
        log("dinput proxy: CreateDevice hooked");
    }
    hr
}

// The remaining dinput8 exports are COM plumbing the game never calls; forward them so
// anything else in the process that does still works.
#[no_mangle]
pub unsafe extern "system" fn DllCanUnloadNow() -> HRESULT {
    let c = CString::new("DllCanUnloadNow").unwrap();
    let p = GetProcAddress(real_dinput8(), c.as_ptr());
    if p.is_null() { return 1; }
    let f: unsafe extern "system" fn() -> HRESULT = std::mem::transmute(p);
    f()
}

#[no_mangle]
pub unsafe extern "system" fn DllGetClassObject(
    rclsid: *const c_void, riid: *const c_void, out: *mut *mut c_void,
) -> HRESULT {
    let c = CString::new("DllGetClassObject").unwrap();
    let p = GetProcAddress(real_dinput8(), c.as_ptr());
    if p.is_null() { return -1; }
    let f: unsafe extern "system" fn(*const c_void, *const c_void, *mut *mut c_void) -> HRESULT =
        std::mem::transmute(p);
    f(rclsid, riid, out)
}

#[no_mangle]
pub unsafe extern "system" fn GetdfDIJoystick() -> *mut c_void {
    let c = CString::new("GetdfDIJoystick").unwrap();
    let p = GetProcAddress(real_dinput8(), c.as_ptr());
    if p.is_null() { return ptr::null_mut(); }
    let f: unsafe extern "system" fn() -> *mut c_void = std::mem::transmute(p);
    f()
}

#[no_mangle]
pub unsafe extern "system" fn Direct3DCreate9Ex(sdk: u32, out: *mut *mut c_void) -> HRESULT {
    let p = real_proc("Direct3DCreate9Ex");
    if p.is_null() {
        return -1;
    }
    let f: unsafe extern "system" fn(u32, *mut *mut c_void) -> HRESULT = std::mem::transmute(p);
    f(sdk, out)
}

// D3DPERF_* are profiling no-ops for our purposes; forward them so any tool that pokes
// them still works. Fable3.exe itself imports none of these.
#[no_mangle]
pub unsafe extern "system" fn D3DPERF_BeginEvent(col: u32, name: *const u16) -> i32 {
    let p = real_proc("D3DPERF_BeginEvent");
    if p.is_null() { return 0; }
    let f: unsafe extern "system" fn(u32, *const u16) -> i32 = std::mem::transmute(p);
    f(col, name)
}

#[no_mangle]
pub unsafe extern "system" fn D3DPERF_EndEvent() -> i32 {
    let p = real_proc("D3DPERF_EndEvent");
    if p.is_null() { return 0; }
    let f: unsafe extern "system" fn() -> i32 = std::mem::transmute(p);
    f()
}

#[no_mangle]
pub unsafe extern "system" fn D3DPERF_SetMarker(col: u32, name: *const u16) {
    let p = real_proc("D3DPERF_SetMarker");
    if p.is_null() { return; }
    let f: unsafe extern "system" fn(u32, *const u16) = std::mem::transmute(p);
    f(col, name)
}

#[no_mangle]
pub unsafe extern "system" fn D3DPERF_SetRegion(col: u32, name: *const u16) {
    let p = real_proc("D3DPERF_SetRegion");
    if p.is_null() { return; }
    let f: unsafe extern "system" fn(u32, *const u16) = std::mem::transmute(p);
    f(col, name)
}

#[no_mangle]
pub unsafe extern "system" fn D3DPERF_QueryRepeatFrame() -> BOOL {
    let p = real_proc("D3DPERF_QueryRepeatFrame");
    if p.is_null() { return 0; }
    let f: unsafe extern "system" fn() -> BOOL = std::mem::transmute(p);
    f()
}

#[no_mangle]
pub unsafe extern "system" fn D3DPERF_SetOptions(opts: DWORD) {
    let p = real_proc("D3DPERF_SetOptions");
    if p.is_null() { return; }
    let f: unsafe extern "system" fn(DWORD) = std::mem::transmute(p);
    f(opts)
}

#[no_mangle]
pub unsafe extern "system" fn D3DPERF_GetStatus() -> DWORD {
    let p = real_proc("D3DPERF_GetStatus");
    if p.is_null() { return 0; }
    let f: unsafe extern "system" fn() -> DWORD = std::mem::transmute(p);
    f()
}

/// Key poller. Runs on its own thread, completely independent of D3D: the render hooks
/// proved unreliable in this game (the render loop stays healthy but our hooked EndScene
/// stops being reached, which points at the DFA/F3Secu anti-tamper restoring vtables), so
/// input must not depend on them. Writes each keypress to the bridge file; Lua owns the
/// menu state and draws it with GUI.SetCounter, a channel that is already proven here.
unsafe extern "system" fn input_thread(_p: *mut c_void) -> u32 {
    log("input thread started");

    // NO low-level keyboard hook here. Installing one routes all system keyboard input
    // through this thread, and if the thread is not servicing it promptly the whole game
    // hangs on startup - which is exactly what happened. Polling only.
    let mut prev = [false; 4];
    let keys = [VK_F1, VK_UP, VK_DOWN, VK_RETURN];
    let mut ticks: u32 = 0;
    loop {
        ticks += 1;
        // Prove the loop actually runs. Neither build ever logged a heartbeat, so the
        // question is not which key API works - it is whether this thread survives its
        // first iteration at all.
        if ticks <= 3 {
            log(&format!("loop tick {}", ticks));
        }
        // Alive heartbeat every ~10s. Distinguishes "thread died" from "thread running but
        // GetAsyncKeyState never reports a key", which need completely different fixes.
        if ticks % 100 == 0 {
            // Sweep the whole keyboard so we can see whether ANY key is observable from
            // this thread; if the count is always 0 while keys are being pressed, the
            // game is consuming input in a way GetAsyncKeyState cannot see.
            let mut any = 0;
            let mut first = 0;
            for vk in 1..256 {
                if (GetAsyncKeyState(vk) as u16 & 0x8000) != 0 {
                    any += 1;
                    if first == 0 {
                        first = vk;
                    }
                }
            }
            log(&format!("input alive: ticks={} keys_down_now={} first_vk={}", ticks, any, first));
        }
        // Polling. Harmless if the hook already handled the key - the Lua
        // side keys off a sequence number, and a duplicate press is idempotent enough for
        // a menu. Kept because it costs nothing and covers the case where the hook is
        // refused (some systems block low-level hooks).
        for (i, &vk) in keys.iter().enumerate() {
            let down = (GetAsyncKeyState(vk) as u16 & 0x8000) != 0;
            if down && !prev[i] {
                log(&format!("POLL: vk={} -> action {}", vk, i + 1));
                write_key(i as u32 + 1);
            }
            prev[i] = down;
        }
        Sleep(10);
    }
}

/// Publish one keypress. Same atomic temp-then-move as the command writer.
unsafe fn write_key(key: u32) {
    let seq = CMD_ID.fetch_add(1, Ordering::AcqRel) + 1;
    let body = format!("F3KEY = {{ seq = {}, key = {} }}\n", seq, key);
    let tmp = game_path("F3Bridge.tmp");
    let dst = game_path("F3Bridge.lua");
    let h = CreateFileA(
        tmp.as_ptr() as *const i8,
        GENERIC_WRITE,
        0,
        ptr::null_mut(),
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        ptr::null_mut(),
    );
    if h as isize == INVALID_HANDLE {
        return;
    }
    let mut w = 0u32;
    WriteFile(h, body.as_ptr(), body.len() as u32, &mut w, ptr::null_mut());
    CloseHandle(h);
    MoveFileExA(
        tmp.as_ptr() as *const i8,
        dst.as_ptr() as *const i8,
        MOVEFILE_REPLACE_EXISTING,
    );
}

#[no_mangle]
pub extern "system" fn DllMain(h: HMODULE, reason: u32, _reserved: *mut c_void) -> BOOL {
    // Only stash our module handle here; SetWindowsHookEx needs it. Starting a thread or
    // touching files under the Windows loader lock deadlocked the game inside CreateDevice,
    // so all real startup happens lazily from Direct3DCreate9, which the game calls well
    // after loading finishes.
    if reason == 1 {
        SELF_MODULE.store(h as isize, Ordering::Release);
    }
    1
}
