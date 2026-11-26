# GFXD - DIOS Graphics Server

GFXD is a graphics server and a window manager that allows other applications to draw graphics.

GFXD is a userspace program that is provided to the kernel as a binary module via Limine (see `limine.conf`). It must be present as `cdroot/user/gfxd.elf` before building the ISO image.

## Usage

Start the graphics mode from the kernel shell with `gfx start` (or `run gfxd &`). `Ctrl+F1` switches back to the shell, `Ctrl+F2` back to the server, `Ctrl+Q` ends it politely, `Ctrl+F3` kills it (those hotkeys are handled by the kernel).

## Window hints (desktop shells)

An application can ask the window manager to treat its window specially by sending `GFX_EV_WM_HINTS` (flags `GFX_WIN_*`, see `ulib/gfx/proto.d`). From `ulib.gfx.window`:

| Flag | Effect |
|---|---|
| `GFX_WIN_BORDERLESS` | no frame, title bar or close button; the window is just its drawable area |
| `GFX_WIN_FIXED` | the user cannot move it |
| `GFX_WIN_BOTTOM` | always below all other windows; clicking it never raises it above them, and it does not take the keyboard when it appears |
| `GFX_WIN_POSITION` | put the drawable area at a given screen position |

`GFX_WIN_DESKTOP` is all four together. The flags are independent, so e.g. `BORDERLESS` alone gives a plain undecorated normal window.

```d
GfxInfo info;
ugfxInfo(&info);

Window bar;
windowCreateDesktop(&bar, info.width, 32, 0, info.height - 32);   // taskbar along the bottom edge
// ... draw, windowCommit(&bar), then loop on windowPoll() as usual
```

`windowSetHints()` / `windowSetPosition()` change the hints of an open window. Hints are requests handled by the server: the client library re-sends them whenever a server (re)starts, so a desktop program may be started before `gfx start`, but it must keep calling `windowPoll()`.

Bottom windows form their own layer: among themselves they stack normally (a click raises one over the other bottom windows). Mouse clicks on a bottom window are delivered to it like for any window, so taskbar buttons and widgets work.
