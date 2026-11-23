# System Call

The system call is a DIOS kernel function call that can be made from applications. System calls are made with a single entry, `sys_call`, for all the functions.

## Specification

`long sys_call(ulong nr, ulong a0, ulong a1, ulong a2)`

Calls a kernel function. `nr` is a function number, `a0`, `a1`, `a2` are parameters.

Supported function numbers:

- `SYS_EXIT` (0) - terminates the application. Return code is passed via `a0`
- `SYS_WRITE` (1) - writes to the standard output (the kernel shell, if running in text mode). `a0` is the start pointer, `a1` is the number of characters to write
- `SYS_GETKEY` (2) - returns currently pressed ASCII key code. If `a0` is 0, immediately returns -1 if no key is pressed, otherwise waits until a key is pressed
- `SYS_SLEEP` (3) - stops execution for a given time in milliseconds (`a0`)
- `SYS_TICKS` (4) - returns the number of millisecond ticks since the system start
- `SYS_CLEAR` (5) - clears the standard ouput (the kernel shell, if running in text mode)
- `SYS_OPEN` (6) - opens a file/directory. `a0` is the path. Returns a descriptor on success, or -1 on error
- `SYS_READ` (7) - reads bytes from the file at the current offset. `a0` is the file descriptor, `a1` is the destination buffer, `a2` is the number of bytes to read. Returns number of bytes actually read (0 = end of file), or -1 on error
- `SYS_CLOSE` (8) - closes the file. `a0` is the file descriptor. Returns 0 on success, -1 on error
- `SYS_SEEK` (9) - jumps to a byte offset in the file. `a0` is the file descriptor, `a1` is the offset, `a2` is the origin for the new offset (`SEEK_SET = 0`, `SEEK_CUR = 1`, `SEEK_END = 2`). Returns a new position, or -1 on error
- `SYS_STAT` (10) - retrieves file stats. `a0` is the file descriptor, `a1` is the pointer to an output `UStat` structure. Returns 0 on success, -1 if the path does not exist
- `SYS_READDIR` (11) - retrieves the next entry of an opened directory. `a0` is the directory descriptor, `a1` is the pointer to an output `UDirent` structure. Returns 1 if filled in, 0 if there are no more entries, -1 on error
- `SYS_GETCWD` (12) - writes current working directory into a provided character buffer. `a0` is the pointer, `a1` is the buffer length. Returns CWD length or -1 on error
- `SYS_BRK` (13) - changes the program break. If `a0` is 0, returns the current break; otherwise sets the break to requested, returns the new break or -1 on error
- `SYS_YIELD` (14) - let other programs run now
- `SYS_GETPID` (15) - task ID of this program.

## Data Types

Used in `SYS_STAT`:

```
struct UStat
{
    ulong size;
    uint mtime; // DOS timestamp: (year-1980)<<25 | month<<21 | day<<16 | hour<<11 | min<<5 | sec/2
    uint isDir;
}
```

Used in `SYS_READDIR`:

```
struct UDirent
{
    ulong size;
    uint mtime;
    uint isDir;
    char[256] name;
}
```
