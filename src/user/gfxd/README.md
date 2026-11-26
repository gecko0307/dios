# GFXD - DIOS Graphics Server

GFXD is a graphics server and a window manager that allows other applications to draw graphics.

GFXD is a userspace program that is provided to the kernel as a binary module via Limine (see `limine.conf`). It must be present as `cdroot/user/gfxd.elf` before building the ISO image.

## Usage

Start the graphics mode from the kernel shell with `gfx start` (or `run gfxd &`). `Ctrl+F1` switches back to the shell, `Ctrl+F2` back to the server, `Ctrl+Q` ends it politely, `Ctrl+F3` kills it (those hotkeys are handled by the kernel).
