module dios.core.keyboard;

import dios.core.port;

// ---------------------------------------------------------------------------
// Key events. PS/2 and USB keyboards both feed this one queue; the main loop
// drains it. Everything here runs in main-loop context (the PS/2 IRQ handler
// only queues raw bytes, USB is polled), so no locking is needed.
//
// An event is a set-1 make code plus two flags: whether Shift was held when the
// key went down, and whether the key is "extended" (E0-prefixed on PS/2:
// arrows, Home/End/PgUp/PgDn/Insert/Delete, keypad Enter and "/", right Ctrl/Alt).
// ---------------------------------------------------------------------------
enum uint KEYQ_SIZE = 64;       // power of two

struct KeyQueue
{
    ushort[KEYQ_SIZE] keys;     // (extended << 9) | (shift << 8) | scancode
    uint head;
    uint tail;
    uint dropped;
}

__gshared KeyQueue keyQueue;

extern(C):

void kRestartKeyboard() @nogc nothrow
{
   ubyte data = kPortReadByte(0x61);
   kPortWriteByte(0x61, data | 0x80); // Disables the keyboard
   kPortWriteByte(0x61, data & 0x7F); // Enables the keyboard
}

enum KYBRD_ENC_INPUT_BUF = 0x60;
enum KYBRD_ENC_CMD_REG = 0x60;

enum KYBRD_CTRL_STATS_REG = 0x64;
enum KYBRD_CTRL_CMD_REG = 0x64;

enum KYBRD_CTRL_STATS_MASK_OUT_BUF  = 1;
enum KYBRD_CTRL_STATS_MASK_IN_BUF   = 2;
enum KYBRD_CTRL_STATS_MASK_SYSTEM   = 4;
enum KYBRD_CTRL_STATS_MASK_CMD_DATA = 8;
enum KYBRD_CTRL_STATS_MASK_LOCKED   = 0x10;
enum KYBRD_CTRL_STATS_MASK_AUX_BUF  = 0x20;
enum KYBRD_CTRL_STATS_MASK_TIMEOUT  = 0x40;
enum KYBRD_CTRL_STATS_MASK_PARITY   = 0x80;

enum KYBRD_CTRL_CMD_SELF_TEST = 0xAA;
enum KYBRD_CTRL_CMD_ENABLE    = 0xAE;

/// Read status from keyboard controller.
ubyte kKbdReadStatus() @nogc nothrow
{
    return kPortReadByte(KYBRD_CTRL_STATS_REG);
}

/// Read keyboard encoder buffer
ubyte kKbdEncReadBuffer() @nogc nothrow
{
    return kPortReadByte(KYBRD_ENC_INPUT_BUF);
}

/// Send command byte to keyboard controller
void kKbdSendCmd(ubyte cmd) @nogc nothrow
{
    // Wait for controller input buffer to be clear
    while (1)
        if ((kKbdReadStatus() & KYBRD_CTRL_STATS_MASK_IN_BUF) == 0)
            break;

    kPortWriteByte(KYBRD_CTRL_CMD_REG, cmd);
}

bool kKbdSelfTest() @nogc nothrow
{
    kKbdSendCmd(KYBRD_CTRL_CMD_SELF_TEST);
    // Wait for output buffer to be full
    while (1)
        if (kKbdReadStatus() & KYBRD_CTRL_STATS_MASK_OUT_BUF)
            break;
    // if output buffer == 0x55, test passed
    return (kKbdEncReadBuffer() == 0x55) ? true : false;
}

void kKbdEnable() @nogc nothrow
{
    kKbdSendCmd(0xFF);
    kKbdSendCmd(KYBRD_CTRL_CMD_ENABLE);
}

void kKbdFlushBuffer() @nogc nothrow
{
    while ((kPortReadByte(0x64) & 1) != 0)
    {
        ubyte tmp = kPortReadByte(0x60);
    }
}

immutable ubyte[128] scancodeToAscii = [
    0,  27, '1', '2', '3', '4', '5', '6',   // 0x00-0x07
    '7', '8', '9', '0', '-', '=', 8, 9,     // 0x08-0x0F
    'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', // 0x10-0x17
    'o', 'p', '[', ']', 13, 0, 'a', 's',    // 0x18-0x1F
    'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', // 0x20-0x27
    '\'', '`', 0, '\\', 'z', 'x', 'c', 'v', // 0x28-0x2F
    'b', 'n', 'm', ',', '.', '/', 0, '*',   // 0x30-0x37
    0, ' ', 0, 0, 0, 0, 0, 0                // 0x38-0x3F
];

// Same layout as scancodeToAscii, with Shift held (US layout).
immutable ubyte[128] scancodeToAsciiShift = [
    0,  27, '!', '@', '#', '$', '%', '^',   // 0x00-0x07
    '&', '*', '(', ')', '_', '+', 8, 9,     // 0x08-0x0F
    'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', // 0x10-0x17
    'O', 'P', '{', '}', 13, 0, 'A', 'S',    // 0x18-0x1F
    'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', // 0x20-0x27
    '"', '~', 0, '|', 'Z', 'X', 'C', 'V',   // 0x28-0x2F
    'B', 'N', 'M', '<', '>', '?', 0, '*',   // 0x30-0x37
    0, ' ', 0, 0, 0, 0, 0, 0                // 0x38-0x3F
];

char scancodeToChar(ubyte code, bool shift = false) @nogc nothrow
{
    if (code >= scancodeToAscii.length)
        return 0;
    return cast(char)(shift ? scancodeToAsciiShift[code] : scancodeToAscii[code]);
}

ubyte kKbdGetKey() @nogc nothrow
{
    while ((kPortReadByte(0x64) & 1) == 0)
        asm @nogc nothrow { hlt; }
    return kPortReadByte(0x60);
}

/// Caps Lock state. Toggled by the producers (see keyCapsToggle), snapshotted into each event.
__gshared bool keyCapsLock;

enum ushort KEYF_SHIFT = 0x100;
enum ushort KEYF_EXT   = 0x200;
enum ushort KEYF_CTRL  = 0x400;
enum ushort KEYF_CAPS  = 0x800;

/// One key press as the shell sees it.
struct KeyEvent
{
    ubyte scancode;     // set-1 make code
    bool shift;
    bool ctrl;
    bool caps;          // Caps Lock was on
    bool extended;      // arrows, Home/End/PgUp/PgDn/Insert/Delete, right Ctrl/Alt
}

/// Flip Caps Lock. Producers call this once per physical press (no auto-repeat).
void keyCapsToggle() @nogc nothrow
{
    keyCapsLock = !keyCapsLock;
}

/// Queue a key press. Returns false (and counts a drop) if the queue is full.
bool keyPush(ubyte scancode, bool shift, bool extended, bool ctrl = false) @nogc nothrow
{
    uint next = keyQueue.head + 1;
    if (next - keyQueue.tail > KEYQ_SIZE)
    {
        keyQueue.dropped++;
        return false;
    }
    keyQueue.keys[keyQueue.head & (KEYQ_SIZE - 1)] =
        cast(ushort)(scancode | (shift ? KEYF_SHIFT : 0) | (extended ? KEYF_EXT : 0) |
                     (ctrl ? KEYF_CTRL : 0) | (keyCapsLock ? KEYF_CAPS : 0));
    keyQueue.head = next;
    return true;
}

/// Next key press, in order, with everything the event carries. Keypad Enter
/// and keypad "/" (extended 0x1C / 0x35) are reported as their plain
/// counterparts; every other extended key keeps its `extended` flag.
bool keyPopEvent(KeyEvent* ev) @nogc nothrow
{
    if (keyQueue.tail == keyQueue.head)
        return false;
    ushort e = keyQueue.keys[keyQueue.tail & (KEYQ_SIZE - 1)];
    keyQueue.tail++;
    ev.scancode = cast(ubyte)(e & 0xFF);
    ev.shift = (e & KEYF_SHIFT) != 0;
    ev.extended = (e & KEYF_EXT) != 0;
    ev.ctrl = (e & KEYF_CTRL) != 0;
    ev.caps = (e & KEYF_CAPS) != 0;
    if (ev.extended && (ev.scancode == 0x1C || ev.scancode == 0x35))
        ev.extended = false;
    return true;
}

/// Printable/control character for an event (0 if none). Caps Lock only flips
/// letters; Ctrl+letter gives 1..26.
char keyEventChar(const(KeyEvent)* ev) @nogc nothrow
{
    if (ev.extended || ev.scancode >= scancodeToAscii.length)
        return 0;
    ubyte lower = scancodeToAscii[ev.scancode];
    bool letter = lower >= 'a' && lower <= 'z';
    if (ev.ctrl)
        return letter ? cast(char)(lower - 'a' + 1) : cast(char)0;
    bool useShift = letter ? (ev.shift != ev.caps) : ev.shift;
    return cast(char)(useShift ? scancodeToAsciiShift[ev.scancode] : lower);
}
