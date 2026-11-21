module dios.core.mouse;

// One cursor shared by every pointing device (PS/2 and USB both call mouseMove).
// Coordinates are screen pixels, y grows downwards.

struct MouseState
{
    int x;
    int y;
    int wheel;
    uint xBound;     // maximum x
    uint yBound;     // maximum y
    ubyte buttons;   // 0x1 left, 0x2 right, 0x4 middle
}

__gshared MouseState mouse;

extern(C):

void mouseInit(uint xBound, uint yBound) @nogc nothrow
{
    mouse.xBound = xBound;
    mouse.yBound = yBound;
    mouse.x = cast(int)(xBound / 2);
    mouse.y = cast(int)(yBound / 2);
    mouse.wheel = 0;
    mouse.buttons = 0;
}

void mouseMove(int dx, int dy, ubyte buttons) @nogc nothrow
{
    long nx = cast(long)mouse.x + dx;
    long ny = cast(long)mouse.y + dy;
    if (nx < 0) nx = 0;
    if (ny < 0) ny = 0;
    if (nx > cast(long)mouse.xBound) nx = mouse.xBound;
    if (ny > cast(long)mouse.yBound) ny = mouse.yBound;
    mouse.x = cast(int)nx;
    mouse.y = cast(int)ny;
    mouse.buttons = buttons;
}
