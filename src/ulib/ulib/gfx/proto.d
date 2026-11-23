/*
This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the software
to the public domain. We make this dedication for the benefit of the
public at large and to the detriment of our heirs and successors.
We intend this dedication to be an overt act of relinquishment in 
perpetuity of all present and future rights to this software under
copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <https://unlicense.org>
*/

module ulib.gfx.proto;

/**
 * DIOS graphics protocol: the system calls of the graphics server support (kernel side:
 * src/kernel/dios/core/gfxsrv.d - read the comment at its top first) and the structures
 * that go through them. Everything here must stay identical to the kernel's definitions.
 *
 * Two roles:
 *   client - a normal program that wants a drawable area: ugfxSurfaceCreate(), draw into the
 *            pixels, ugfxSurfaceCommit(), react to events from ugfxPoll(). Most programs
 *            should use ulib.gfx.window instead of calling these directly.
 *   server - THE program that shows the clients' surfaces on screen (src/user/gfxd).
 *            ugfxServerBegin() takes the screen; ugfxPoll() delivers what happens; the
 *            server maps surfaces, composes them in a back buffer and ugfxServerPresent()s it.
 *
 * Pixels are 32 bit, 0x00RRGGBB, rows are `stride` bytes apart.
 */

import ulib.dios.sys;

enum ulong SYS_GFX_INFO            = 18;
enum ulong SYS_GFX_SERVER_BEGIN    = 19;
enum ulong SYS_GFX_SERVER_END      = 20;
enum ulong SYS_GFX_SERVER_PRESENT  = 21;
enum ulong SYS_GFX_SERVER_MAP      = 22;
enum ulong SYS_GFX_SERVER_UNMAP    = 23;
enum ulong SYS_GFX_SURFACE_CREATE  = 24;
enum ulong SYS_GFX_SURFACE_COMMIT  = 25;
enum ulong SYS_GFX_SURFACE_DESTROY = 26;
enum ulong SYS_GFX_SEND            = 27;
enum ulong SYS_GFX_POLL            = 28;

// Event types (GfxEvent.type). Meaning of the fields a, b, c, d:
enum uint GFX_EV_NONE           = 0;
// kernel -> server
enum uint GFX_EV_SURFACE_NEW    = 1;    // surface; a = width, b = height, c = owner task id
enum uint GFX_EV_SURFACE_DAMAGE = 2;    // surface; a, b, c, d = x, y, w, h that changed (merged)
enum uint GFX_EV_SURFACE_GONE   = 3;    // surface; the owner is gone. Drop it, then ugfxServerUnmap() it
enum uint GFX_EV_VISIBLE        = 4;    // a = 1: you own the screen now (repaint ALL), 0: you lost it
enum uint GFX_EV_KEY            = 16;   // a = set-1 scancode, b = ASCII (0: none), c = GFX_MOD_*. Presses only
enum uint GFX_EV_MOUSE          = 17;   // a = x, b = y, c = buttons (1 left, 2 right, 4 middle), d = wheel delta
// kernel -> client
enum uint GFX_EV_SERVER         = 32;   // surface; a = 1: a server is running now, 0: it stopped
// server -> client: conventions only, the kernel passes them on untouched
enum uint GFX_EV_FOCUS          = 33;   // a = 1 gained, 0 lost keyboard focus
enum uint GFX_EV_CLOSE          = 34;   // the user asked to close the window
// From here on: free for you. Clients may only send these (to the server); the server may send anything.
enum uint GFX_EV_USER           = 0x1000;

// GfxEvent.c of GFX_EV_KEY
enum uint GFX_MOD_SHIFT = 1;
enum uint GFX_MOD_CTRL  = 2;
enum uint GFX_MOD_CAPS  = 4;
enum uint GFX_MOD_EXT   = 8;            // arrow keys, Home, End, Delete...

// GfxEvent.c of GFX_EV_MOUSE
enum uint GFX_BTN_LEFT   = 1;
enum uint GFX_BTN_RIGHT  = 2;
enum uint GFX_BTN_MIDDLE = 4;

// GfxInfo.flags
enum uint GFX_INFO_SERVER  = 1;         // a server is running
enum uint GFX_INFO_VISIBLE = 2;         // ... and it has the screen

struct GfxInfo
{
    uint width;         // screen size in pixels
    uint height;
    uint flags;         // GFX_INFO_*
    uint serverTask;    // task id of the server, 0 if none
}

struct GfxRect
{
    int x, y, w, h;
}

struct GfxSurfaceDesc
{
    uint id;            // create: out. server map: in
    uint width;         // create: in. server map: out
    uint height;        // create: in. server map: out
    uint stride;        // out: bytes per row
    uint* pixels;       // out: first pixel, in the address space of the caller
    uint owner;         // server map: out: task id of the owner
    uint reserved;
}

struct GfxEvent
{
    uint type;          // GFX_EV_*
    uint surface;       // the surface it is about, 0 if none
    int a, b, c, d;
    uint time;          // milliseconds since boot
    uint reserved;
}

static assert(GfxInfo.sizeof == 16);
static assert(GfxRect.sizeof == 16);
static assert(GfxSurfaceDesc.sizeof == 32);
static assert(GfxEvent.sizeof == 32);

extern(C):

/// Screen size and whether a graphics server is running. 0 on success.
int ugfxInfo(GfxInfo* info) @nogc nothrow
{
    return cast(int)sys_call(SYS_GFX_INFO, cast(ulong)info, 0, 0);
}

/// Next event for this program (the server's events, if it is the server). Waits up to
/// `timeoutMs` milliseconds: 0 = do not wait, negative = wait for as long as it takes.
/// Returns 1 if `ev` was filled in, 0 on timeout, -1 on error.
int ugfxPoll(GfxEvent* ev, long timeoutMs) @nogc nothrow
{
    return cast(int)sys_call(SYS_GFX_POLL, cast(ulong)ev, cast(ulong)timeoutMs, 0);
}

/// Sends an event. From a client: to the server (type must be >= GFX_EV_USER; `surface` is
/// one of yours or 0). From the server: to the owner of `surface` (any type). 0 on success.
int ugfxSend(uint surface, const(GfxEvent)* ev) @nogc nothrow
{
    return cast(int)sys_call(SYS_GFX_SEND, cast(ulong)surface, cast(ulong)ev, 0);
}

// ---- client ----

/// Creates a drawable area: fill in `width` and `height`; on success `id`, `stride` and
/// `pixels` are set and 0 is returned. The pixels start out black (0).
int ugfxSurfaceCreate(GfxSurfaceDesc* desc) @nogc nothrow
{
    return cast(int)sys_call(SYS_GFX_SURFACE_CREATE, cast(ulong)desc, 0, 0);
}

/// Tells the server that `rect` of the surface changed (null: all of it).
int ugfxSurfaceCommit(uint surface, const(GfxRect)* rect) @nogc nothrow
{
    return cast(int)sys_call(SYS_GFX_SURFACE_COMMIT, cast(ulong)surface, cast(ulong)rect, 0);
}

/// Gives the surface back. Its pixels are no longer yours.
int ugfxSurfaceDestroy(uint surface) @nogc nothrow
{
    return cast(int)sys_call(SYS_GFX_SURFACE_DESTROY, cast(ulong)surface, 0, 0);
}

// ---- server ----

/// Becomes THE graphics server and takes the screen. Fails (-1) if there already is one.
/// Surfaces of programs that are already running are announced as GFX_EV_SURFACE_NEW.
int ugfxServerBegin() @nogc nothrow
{
    return cast(int)sys_call(SYS_GFX_SERVER_BEGIN, 0, 0, 0);
}

/// Gives up the server role (the shell gets the screen back). Also happens when the program exits.
int ugfxServerEnd() @nogc nothrow
{
    return cast(int)sys_call(SYS_GFX_SERVER_END, 0, 0, 0);
}

/// Copies the back buffer to the screen: all of it, or just `rect`. `pixels` is a
/// screen-sized buffer of 0x00RRGGBB pixels whose rows are `pitchBytes` apart (0: tightly
/// packed, width * 4). Returns 1 if it was copied, 0 if the shell has the screen right now
/// (nothing happened), -1 on error.
int ugfxServerPresent(const(uint)* pixels, const(GfxRect)* rect, uint pitchBytes) @nogc nothrow
{
    return cast(int)sys_call(SYS_GFX_SERVER_PRESENT, cast(ulong)pixels, cast(ulong)rect, cast(ulong)pitchBytes);
}

/// Maps the surface `desc.id` into this program: on success width, height, stride, pixels
/// and owner are set. Mapping twice gives the same address.
int ugfxServerMap(GfxSurfaceDesc* desc) @nogc nothrow
{
    return cast(int)sys_call(SYS_GFX_SERVER_MAP, cast(ulong)desc, 0, 0);
}

/// Lets go of a mapped surface. Do this after GFX_EV_SURFACE_GONE, once nothing uses its
/// pixels any more: the memory is only freed then.
int ugfxServerUnmap(uint surface) @nogc nothrow
{
    return cast(int)sys_call(SYS_GFX_SERVER_UNMAP, cast(ulong)surface, 0, 0);
}
