# The Graphics Stack

The DIOS kernel does not draw windows by itself. Instead, it provides a protocol that connects userspace graphics server (the program that draws windows) with graphics clients (applications that need a window).

The screen belongs either to the console (the kernel shell) or to the graphics server. `Ctrl+F1` shows the shell, `Ctrl+F2` shows the server, `Ctrl+F3` stops it. If the server crashes, the console comes back. While the server is on screen the console keeps drawing into its scene buffer, so the shell is exactly as it was when you return to it.

A client asks for a drawable BGRA pixel buffer of WxH (4 bytes per pixel, 0xAARRGGBB in little-endian). The kernel allocates the pages and maps them into the client, and into the server when it asks. The client draws, then "commits" (damage rectangle); the server sees that and composes. Pages are freed only when nobody can touch them any more: a surface whose owner is gone stays alive until the server has unmapped it.

The server draws into its own back buffer and asks the kernel to copy it (or a rectangle of it) to video memory. The kernel only does that while the server is on screen, so a server that does not know it was switched away can do no harm.

## Graphics Protocol API

`int ugfxInfo(GfxInfo* info)`

Gets the kernel graphics info (screen size; whether a graphics server is running). Returns 0 on success.

`int ugfxPoll(GfxEvent* ev, long timeoutMs)`

Next event for this program (the server's events, if it is the server). Waits up to `timeoutMs` milliseconds: 0 = do not wait, negative = wait for as long as it takes. Returns 1 if `ev` was filled in, 0 on timeout, -1 on error.

`int ugfxSend(uint surface, const(GfxEvent)* ev)`

Sends an event. From a client: to the server (type must be >= GFX_EV_USER; `surface` is one of yours or 0). From the server: to the owner of `surface` (any type). Returns 0 on success.

`int ugfxSurfaceCreate(GfxSurfaceDesc* desc)`

Creates a drawable area: fill in `width` and `height`; on success `id`, `stride` and `pixels` are set and 0 is returned. The pixels start out black (0).

`int ugfxSurfaceCommit(uint surface, const(GfxRect)* rect)`

Tells the server that `rect` part of the surface is changed (`null`: all of it).

`int ugfxSurfaceDestroy(uint surface)`

Gives the surface back. Its pixels are no longer yours.

`int ugfxServerBegin()`

Application becomes the graphics server and takes the screen. Fails (returns -1) if there already is one. Surfaces of programs that are already running are announced as `GFX_EV_SURFACE_NEW`.

`int ugfxServerEnd()`

Gives up the server role. The shell gets the screen back. Also happens when the program exits.

`int ugfxServerPresent(const(uint)* pixels, const(GfxRect)* rect, uint pitchBytes)`

Copies the back buffer to the screen: all of it, or just `rect`. `pixels` is a screen-sized buffer of `0x00RRGGBB` pixels whose rows are `pitchBytes` apart (0: tightly packed, `width * 4`). Returns 1 if it was copied, 0 if the shell has the screen right now (nothing happened), -1 on error.

`int ugfxServerMap(GfxSurfaceDesc* desc)`

Maps the surface `desc.id` into this program: on success width, height, stride, pixels and owner are set. Mapping twice gives the same address.

`int ugfxServerUnmap(uint surface)`

Lets go of a mapped surface. Do this after GFX_EV_SURFACE_GONE, once nothing uses its pixels any more: the memory is only freed then.

## Canvas

TODO

## Window

`bool windowCreate(Window* win, uint width, uint height)`

Opens a window of `width` x `height` pixels. Returns `false` if it could not be created (too big, too many windows, out of memory).

`void windowSetHints(Window* win, uint flags, int x, int y)`

Asks the window manager to treat the window in a special way: `flags` is a combination of `GFX_WIN_*` (0 = an ordinary window again). With `GFX_WIN_POSITION` the window is put at x, y on the screen (its top left drawable pixel); without it x and y are ignored and the window stays where it is.

`void windowSetPosition(Window* win, int x, int y)`

Moves a window that has the `GFX_WIN_POSITION` hint (or gives it one) to x, y on the screen.

`bool windowCreateDesktop(Window* win, uint width, uint height, int x, int y)`

Opens a window for a desktop shell (a background, a taskbar, a widget): no frame, cannot be moved by the user, always below all other windows, at x, y on the screen. The size of the screen is in `ugfxInfo`.

`void windowCommit(Window* win)`

Tells the server that all of the window changed.

`void windowCommitRect(Window* win, int x, int y, int w, int h)`

Tells the server that only `x`, `y`, `w`, `h` changed (cheaper when it can do something with that).

`bool windowPoll(Window* win, GfxEvent* ev, long timeoutMs)`

The next event for this program (see `GFX_EV_*`). Waits up to `timeoutMs`: 0 = do not wait, negative = for as long as it takes. False if there was none. Typical events for a window: `GFX_EV_KEY`, `GFX_EV_MOUSE` (coordinates relative to the window), `GFX_EV_FOCUS`, `GFX_EV_CLOSE`; and `GFX_EV_SERVER` (a server started or stopped).

`void windowClose(Window* win)`

Closes the window. The canvas must not be used afterwards.

## Image Loading

TODO
