module core.keyboard;

import core.port;

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

char scancodeToChar(ubyte code) @nogc nothrow
{
    if (code >= scancodeToAscii.length)
        return 0;
    return cast(char)scancodeToAscii[code];
}

ubyte kKbdGetKey() @nogc nothrow
{
    while ((kPortReadByte(0x64) & 1) == 0)
        asm @nogc nothrow { hlt; }
    return kPortReadByte(0x60);
}
