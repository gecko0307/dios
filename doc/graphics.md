# Graphics Subsystem

The DIOS kernel does not draw windows by itself. Instead, it provides a protocol that connects userspace graphics server (the program that draws windows) with graphics clients (normal applications).

The screen belongs either to the console (the kernel shell) or to the graphics server. `Ctrl+F1` shows the shell, `Ctrl+F2` shows the server, `Ctrl+F3` stops it. If the server crashes, the console comes back. While the server is on screen the console keeps drawing into its scene buffer, so the shell is exactly as it was when you return to it.

A client asks for a drawable pixel buffer of WxH (XRGB, 4 bytes per pixel). The kernel allocates the pages and maps them into the client, and into the server when it asks. The client draws, then "commits" (damage rectangle); the server sees that and
composes. Pages are freed only when nobody can touch them any more: a surface whose owner is gone stays alive until the server has unmapped it.

The server draws into its own back buffer and asks the kernel to copy it (or a rectangle of it) to video memory. The kernel only does that while the server is on screen, so a server that does not know it was switched away can do no harm.

## Usage

TODO
