# System Call

The system call is a DIOS kernel function call that can be made from applications. System calls are made with a single entry, `sys_call`, for all the functions.

## Specification

`long sys_call(ulong nr, ulong a0, ulong a1, ulong a2)`

Calls a kernel function. `nr` is a function number, `a0`, `a1`, `a2` are parameters.

Kernel functions are organized to groups. There are 10 standard groups with 100 reserved function numbers in each. This allows to extend each group without breaking the ABI in the future.

- `SYS_GROUP1` - functions 0-99: process control, memory control, system info
- `SYS_GROUP2` - functions 100-199: filesystem control
- `SYS_GROUP3` - functions 200-299: channel control
- `SYS_GROUP4` - 
- `SYS_GROUP5` - 
- `SYS_GROUP6` - 
- `SYS_GROUP7` - 
- `SYS_GROUP8` - 
- `SYS_GROUP9` - 
- `SYS_GROUP10` - 

Supported function numbers:

- `SYS_EXIT` (0) - terminates the application. Return code is passed via `a0`
- `SYS_WRITE` (1) - writes to the standard output (the kernel shell, if running in text mode, or the current output channel if running in a userspace terminal). `a0` is the start pointer, `a1` is the number of characters to write
- `SYS_GETKEY` (2) - returns currently pressed ASCII key code. If `a0` is 0, immediately returns -1 if no key is pressed, otherwise waits until a key is pressed
- `SYS_SLEEP` (3) - stops execution for a given time in milliseconds (`a0`)
- `SYS_TICKS` (4) - returns the number of millisecond ticks since the system start
- `SYS_CLEAR` (5) - clears the standard ouput (the kernel shell, if running in text mode)
- `SYS_BRK` (6) - changes the program break. If `a0` is 0, returns the current break; otherwise sets the break to requested, returns the new break or -1 on error
- `SYS_YIELD` (7) - let other programs run now
- `SYS_GETPID` (8) - returns task ID of the current program.
- `SYS_DATETIME` (9) - retrieves current date and time. `a0` is a pointer to an output `DateTime` struct. Returns 0
- `SYS_RANDOM` (10) - generates a random number. This function currently directly uses a hardware RNG (RDRAND)
- `SYS_SPAWN` (11) - executes a userspace program (ELF64 binary). `a0` is the path to an executable, `a1` is a zero-terminated arguments string, `a2` - stdout descriptor (where `SYS_WRITE` output goes): `STDOUT_CONSOLE`, `STDOUT_INHERIT`, or a channel from `SYS_TTY_CREATE`
- `SYS_STR` (12) - retrieves a system info string to a user-provided buffer. `a0` - character buffer, `a1` - buffer size, `a2` - string identifier: `SYS_STR_VERSION`, `SYS_STR_ABOUT`. Returns number of bytes actually written, or -1 on error
- `SYS_TASK_ALIVE` (13) - 
- `SYS_OPEN` (100) - opens a file/directory. `a0` is a zero-terminated path. Returns a descriptor on success, or -1 on error
- `SYS_READ` (101) - reads bytes from the file at the current offset. `a0` is the file descriptor, `a1` is the destination buffer, `a2` is the number of bytes to read. Returns number of bytes actually read (0 = end of file), or -1 on error
- `SYS_FWRITE` (102) - writes bytes to the given file (if opened for writing). `a0` is the file descriptor, `a1` is the input buffer, `a2` is the size of the input in bytes. Returns the number of bytes written (fewer than the input if the volume is full), or -1 on error
- `SYS_CLOSE` (103) - closes the file. `a0` is the file descriptor. Returns 0 on success, -1 on error
- `SYS_SEEK` (104) - jumps to a byte offset in the file. `a0` is the file descriptor, `a1` is the offset, `a2` is the origin for the new offset (`SEEK_SET = 0`, `SEEK_CUR = 1`, `SEEK_END = 2`). Returns a new position, or -1 on error
- `SYS_STAT` (105) - retrieves file stats. `a0` is the file descriptor, `a1` is the pointer to an output `UStat` structure. Returns 0 on success, -1 if the path does not exist
- `SYS_READDIR` (106) - retrieves the next entry of an opened directory. `a0` is the directory descriptor, `a1` is the pointer to an output `UDirent` structure. Returns 1 if filled in, 0 if there are no more entries, -1 on error
- `SYS_GETCWD` (107) - writes current working directory into a provided character buffer. `a0` is the pointer to a buffer, `a1` is the buffer length. Returns CWD length or -1 on error
- `SYS_UNLINK` (108) - deletes a file. `a0` is a zero-terminated path. Returns 0 on success or a negative error code (`UERR_*`)
- `SYS_MKDIR` (109) - creates a directory. `a0` is a zero-terminated path. Returns 0 on success or a negative error code (`UERR_*`)
- `SYS_RMDIR` (110) - removes an empty directory.`a0` is a zero-terminated path. Returns 0 on success or a negative error code (`UERR_*`)
- `SYS_RENAME` (111) - renames or moves a file or directory within one volume; the new name must not exist. `a0` is a zero-terminated path. Returns 0 on success or a negative error code (`UERR_*`)
- `SYS_SYNC` (112) - asks the disks to put everything they hold on the medium
- `SYS_CHDIR` (113) - changes the current directory. Returns 0 on success or a negative error code: UERR_NOT_FOUND or UERR_NOT_DIR
- `SYS_REALPATH` (114) - 
- `SYS_CH_CREATE` (200) - creates a standard output channel. Returns its descriptor (> 0), or -1 if there is no room for another one
- `SYS_CH_READ` (201) - reads from a channel. Does not wait. `a0` is the channel descriptor, `a1` is the pointer to a buffer, `a2` is the buffer size in bytes. Returns the number of bytes read (0 = nothing in the channel right now), or -1 if the channel doesn't belong the program or is gone
- `SYS_CH_STAT` (202) - returns the number of programs that are writing to a channel now (they end by themselves). `a0` is the channel descriptor. Returns -1 on error
- `SYS_CH_CLOSE` (203) - closes a channel. Programs still writing to it lose their output (their `SYS_WRITE` calls fail). It is also closed at exit. `a0` is the channel descriptor.

## Data Types

Used in `SYS_DATETIME`:

```d
struct DateTime
{
    ushort year;
    ubyte month;
    ubyte day;
    ubyte weekday;
    ubyte hour;
    ubyte minute;
    ubyte second;
}
```

Used in `SYS_STAT`:

```d
struct UStat
{
    ulong size;
    uint mtime; // DOS timestamp: (year-1980)<<25 | month<<21 | day<<16 | hour<<11 | min<<5 | sec/2
    uint isDir;
}
```

Used in `SYS_READDIR`:

```d
struct UDirent
{
    ulong size;
    uint mtime;
    uint isDir;
    char[256] name;
}
```
