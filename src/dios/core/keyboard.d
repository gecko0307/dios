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

/// Queue a key press. Returns false (and counts a drop) if the queue is full.
bool keyPush(ubyte scancode, bool shift, bool extended) @nogc nothrow
{
    uint next = keyQueue.head + 1;
    if (next - keyQueue.tail > KEYQ_SIZE)
    {
        keyQueue.dropped++;
        return false;
    }
    keyQueue.keys[keyQueue.head & (KEYQ_SIZE - 1)] =
        cast(ushort)(scancode | (shift ? 0x100 : 0) | (extended ? 0x200 : 0));
    keyQueue.head = next;
    return true;
}

/// Next key press, in order, with everything the event carries.
bool keyPopEx(ubyte* scancode, bool* shift, bool* extended) @nogc nothrow
{
    if (keyQueue.tail == keyQueue.head)
        return false;
    ushort e = keyQueue.keys[keyQueue.tail & (KEYQ_SIZE - 1)];
    keyQueue.tail++;
    *scancode = cast(ubyte)(e & 0xFF);
    *shift = (e & 0x100) != 0;
    *extended = (e & 0x200) != 0;
    return true;
}

/// Text-input view of the queue: like keyPopEx, but extended keys are skipped
/// except keypad Enter (0x1C) and keypad "/" (0x35), which behave like their
/// plain counterparts. (Arrows, PrintScreen etc. must not turn into the
/// keypad digit or "*" that shares their code.)
bool keyPop(ubyte* scancode, bool* shift) @nogc nothrow
{
    ubyte sc;
    bool sh, ext;
    while (keyPopEx(&sc, &sh, &ext))
    {
        if (ext && sc != 0x1C && sc != 0x35)
            continue;
        *scancode = sc;
        *shift = sh;
        return true;
    }
    return false;
}
