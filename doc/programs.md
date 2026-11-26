# DIOS Programs

These programs are available in `/bin` directory and are recognized as commands by the kernel shell and the graphical terminal.

- `echo TEXT` - prints TEXT.
- `about` - prints information about the operating system.
- `pwd` - prints the current directory.
- `ls [PATH]` - lists a directory.
- `touch PATH` - create a file.
- `mkdir PATH` - create a directory.
- `rmdir PATH` - remove a directory.
- `rm PATH` - remove a file.
- `mv SRC DEST` - rename or move within a volume (DEST may be a directory).
- `cp SRC DEST` - copy (DEST may be a directory).
- `write PATH TEXT` - replace file's content by TEXT.
- `append PATH TEXT` - add a line to the file.
- `file PATH [OFFSET]` - prints a text file, optionally starting at a byte offset.
- `time [-u]` - prints current date and time. `-u` prints time since the system boot.
- `timer Ns|Nm|Nh` - sets a timer. N - durarion in seconds, minutes, or hours.
- `gfxd` - starts the graphics mode.
- `gterm` - graphical terminal.
- `image [PATH]` - displays an image (only TGA format is supported currently).
- `blackboard` - a tiny sketching application.
