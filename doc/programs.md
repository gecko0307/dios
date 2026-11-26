# DIOS Programs

These programs are available in `/bin` directory and are recognized as commands by the kernel shell and the graphical terminal.

- `ls [PATH]` - lists a directory.
- `file PATH [OFFSET]` - prints a text file, optionally starting at a byte offset.
- `time [-u]` - prints current date and time. `-u` prints time since the system boot.
- `timer Ns|Nm|Nh` - sets a timer. N - durarion in seconds, minutes, or hours.
- `gfxd` - starts the graphics mode.
- `gterm` - graphical terminal.
- `image [PATH]` - displays an image (only TGA format is supported currently).
