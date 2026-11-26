# System Call

The system call is a DIOS kernel function call that can be made from applications. System calls are made with a single entry, `sys_call`, for all the functions.

## Specification

`long sys_call(ulong nr, ulong a0, ulong a1, ulong a2)`

Calls a kernel function. `nr` is a function number, `a0`, `a1`, `a2` are parameters.

Kernel functions are organized to groups. There are 10 standard groups with 100 reserved function numbers in each. This allows to extend each group without breaking the ABI in the future.

- `SYS_GROUP0` - functions 0-99
- `SYS_GROUP1` - functions 100-199
- `SYS_GROUP2` - functions 200-299
- `SYS_GROUP3` - functions 300-399
- `SYS_GROUP4` - functions 400-499
- `SYS_GROUP5` - functions 500-599
- `SYS_GROUP6` - functions 600-699
- `SYS_GROUP7` - functions 700-799
- `SYS_GROUP8` - functions 800-899
- `SYS_GROUP9` - functions 900-999

In addition to the first 999 reserved functions, 4 extended sets are supported. Their meaning is configuration-defined because the kernel can bind different syscall handler hooks to each set. Currently Extended Set 1 is hardwired to the graphics protocol ABI, but this may change in future.

Each extended set reserves 1000 functions:

- `SYS_EXT1` - functions 1000-1999
- `SYS_EXT2` - functions 2000-2999
- `SYS_EXT3` - functions 3000-3999
- `SYS_EXT4` - functions 4000-4999

## Functions List

Group 1 - process control, memory control, system info:

- `SYS_EXIT` (0) - terminates the application. Return code is passed via `a0`
- `SYS_WRITE` (1) - writes to the standard output (the kernel shell, if running in text mode, or the current output channel if running in a userspace terminal). `a0` is the start pointer, `a1` is the number of characters to write
- `SYS_GETKEY` (2) - returns currently pressed ASCII key code. If `a0` is 0, immediately returns -1 if no key is pressed, otherwise waits until a key is pressed
- `SYS_SLEEP` (3) - stops execution for a given time in milliseconds (`a0`)
- `SYS_TICKS` (4) - returns the number of millisecond ticks since the system start
- `SYS_CLEAR` (5) - clears the standard ouput (the kernel shell, if running in text mode)
- `SYS_BRK` (6) - changes the program break. If `a0` is 0, returns the current break; otherwise sets the break to requested, returns the new break or -1 on error
- `SYS_YIELD` (7) - let other programs run now
- `SYS_GETPID` (8) - returns task ID of the current program
- `SYS_DATETIME` (9) - retrieves current date and time. `a0` is a pointer to an output `DateTime` struct. Returns 0
- `SYS_RANDOM` (10) - generates a random number. This function currently directly uses a hardware RNG (RDRAND)
- `SYS_SPAWN` (11) - executes a userspace program (ELF64 binary). `a0` is the path to an executable, `a1` is a zero-terminated arguments string, `a2` - stdout descriptor (where `SYS_WRITE` output goes): `STDOUT_CONSOLE`, `STDOUT_INHERIT`, or a channel from `SYS_TTY_CREATE`
- `SYS_STR` (12) - retrieves a system information string to a user-provided buffer. `a0` - output buffer, `a1` - buffer size in bytes, `a2` - string identifier: `SYS_STR_VERSION` or `SYS_STR_ABOUT`. Returns number of bytes actually written, or -1 on error
- `SYS_TASK_ALIVE` (13) - returns 1 if a task is running, 0 otherwise. `a0` is a task ID
- `SYS_TASK_FIND` (14) - returns the ID of the oldest running task whose name is the given string. `a0` is the name (without the directory and `.elf` extension). Returns 0 if there is none, -1 on error

Group 2 - filesystem control:

- `SYS_OPEN` (100) - opens a file/directory. `a0` is a zero-terminated path. Returns a descriptor on success, or -1 on error
- `SYS_READ` (101) - reads bytes from the file at the current offset. `a0` is the file descriptor, `a1` is the destination buffer, `a2` is the number of bytes to read. Returns number of bytes actually read (0 = end of file), or -1 on error. Currently `SYS_READ` is limited to 2 MiB per one call
- `SYS_FWRITE` (102) - writes bytes to the given file (if opened for writing). `a0` is the file descriptor, `a1` is the input buffer, `a2` is the size of the input in bytes. Returns the number of bytes written (fewer than the input if the volume is full), or -1 on error
- `SYS_CLOSE` (103) - closes the file. `a0` is the file descriptor. Returns 0 on success, -1 on error
- `SYS_SEEK` (104) - jumps to a byte offset in the file. `a0` is the file descriptor, `a1` is the offset, `a2` is the origin for the new offset (`SEEK_SET = 0`, `SEEK_CUR = 1`, `SEEK_END = 2`). Returns a new position, or -1 on error
- `SYS_STAT` (105) - retrieves file stats. `a0` is the file descriptor, `a1` is the pointer to an output `UStat` structure. Returns 0 on success, -1 if the path does not exist
- `SYS_READDIR` (106) - retrieves the next entry of an opened directory. `a0` is the directory descriptor, `a1` is the pointer to an output `UDirent` structure. Returns 1 if filled in, 0 if there are no more entries, -1 on error
- `SYS_GETCWD` (107) - writes current working directory into a provided buffer. `a0` is the pointer to an output buffer, `a1` is the buffer size in bytes. Returns CWD length or -1 on error
- `SYS_UNLINK` (108) - deletes a file. `a0` is a zero-terminated path. Returns 0 on success or a negative error code (`UERR_*`)
- `SYS_MKDIR` (109) - creates a directory. `a0` is a zero-terminated path. Returns 0 on success or a negative error code (`UERR_*`)
- `SYS_RMDIR` (110) - removes an empty directory.`a0` is a zero-terminated path. Returns 0 on success or a negative error code (`UERR_*`)
- `SYS_RENAME` (111) - renames or moves a file or directory within one volume; the new name must not exist. `a0` is a zero-terminated path. Returns 0 on success or a negative error code (`UERR_*`)
- `SYS_SYNC` (112) - asks the disks to put everything they hold on the medium
- `SYS_CHDIR` (113) - changes the current directory. Returns 0 on success or a negative error code: `UERR_NOT_FOUND` or `UERR_NOT_DIR`
- `SYS_REALPATH` (114) - creates the absolute, normalized form of a given path. `a0` is a null-terminated input path, `a1` is a pointer to an output buffer, `a2` is the buffer size in bytes. Returns the resulting path's length, -1 if it does not fit or a pointer is invalid

Group 3 - channel control:

- `SYS_CH_CREATE` (200) - creates a standard output channel. Returns its descriptor (> 0), or -1 if there is no room for another one
- `SYS_CH_READ` (201) - reads from a channel. Does not wait. `a0` is the channel descriptor, `a1` is the pointer to an output buffer, `a2` is the buffer size in bytes. Returns the number of bytes read (0 = nothing in the channel right now), or -1 if the channel doesn't belong the program or is gone
- `SYS_CH_STAT` (202) - returns the number of programs that are writing to a channel now (they end by themselves). `a0` is the channel descriptor. Returns -1 on error
- `SYS_CH_CLOSE` (203) - closes a channel. Programs still writing to it lose their output (their `SYS_WRITE` calls fail). It is also closed at exit. `a0` is the channel descriptor.

Extended Set 1 - the graphics protocol:

- `SYS_GFX_INFO` (`SYS_EXT1` + 0) - retrieves the graphics information. `a0` is a pointer to `GfxInfo` structure. Returns 0 on success
- `SYS_GFX_SERVER_BEGIN` (`SYS_EXT1` + `1) - process becomes the graphics server and takes ownsership of the screen. Fails (returning -1) if a graphics server is already running. Surfaces of programs that are already running are announced as `GFX_EV_SURFACE_NEW`
- `SYS_GFX_SERVER_END` (`SYS_EXT1` + 2) - gives up the server role, the kernel shell gets the screen back. Also happens when the process terminates
- `SYS_GFX_SERVER_PRESENT` (`SYS_EXT1` + 3) - copies a region of the back buffer to the screen. `a0` is a pointer to a screen-sized buffer of 0x00RRGGBB pixels. `a1` is a pointer to `GfxRect` structure that defines a copy region. `a2` is the buffer pitch in bytes, or 0 for a tightly packed rows (pitch = width * 4). Returns 1 if the buffer was copied, 0 if the shell owns the screen (nothing happens), or -1 on error
- `SYS_GFX_SERVER_MAP` (`SYS_EXT1` + 4) - maps the surface into the current process. `a0` is a pointer to `GfxSurfaceDesc` structure. On success `width`, `height`, `stride`, `pixels` and `owner` are set. Mapping twice gives the same address
- `SYS_GFX_SERVER_UNMAP` (`SYS_EXT1` + 5) - unmaps the surface. `a0` is a surface ID. Do this after `GFX_EV_SURFACE_GONE` event, once nothing uses its pixels anymore; the memory is only freed then
- `SYS_GFX_SURFACE_CREATE` (`SYS_EXT1` + 6) - creates a drawable area. `a0` is a pointer to `GfxSurfaceDesc` structure. Fill in `width` and `height` fields. On success, `id`, `stride` and `pixels` fields are set and 0 is returned. The surface starts out black
- `SYS_GFX_SURFACE_COMMIT` (`SYS_EXT1` + 7) - tells the server that a region of the surface is changed. `a0` is the ID of a surface. `a1` is a pointer to `GfxRect` structure that defines a modified region (if `null`, entire surface is modified)
- `SYS_GFX_SURFACE_DESTROY` (`SYS_EXT1` + 8) - gives the surface back to the server. Its pixels are no longer yours. `a0` is the ID of a surface
- `SYS_GFX_SEND` (`SYS_EXT1` + 9) - sends an event. `a0` is the ID of a surface. `a1` is a pointer to an outgoing `GfxEvent` structure. When sent from a client to the server, `type` must be >= `GFX_EV_USER`; `surface` is one of yours or 0. Returns 0 on success
- `SYS_GFX_POLL` (`SYS_EXT1` + 10) - polls for the next event for this process. `a0` is a pointer to an incoming `GfxEvent` structure. `a1` is wait time in milliseconds (0 = don't wait, negative value = wait for as long as it takes). Returns 1 if the event was receoved, 0 on timeout, -1 on error.

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

Used in the graphics protocol:

```d
struct GfxInfo
{
    uint width;         // display width in pixels
    uint height;        // display height in pixels
    uint flags;         // `GFX_INFO_*`
    uint serverTask;    // task id of the server, 0 if none is running
}
```

```d
struct GfxRect
{
    int x, y, w, h;
}
```

```d
struct GfxSurfaceDesc
{
    uint id;           // surface ID
    uint width;        // surface width in pixels
    uint height;       // surface height in pixels
    uint stride;       // bytes per row
    uint* pixels;      // pointer to the first (upper-left) pixel
    uint owner;        // 
    uint reserved;     // 
}
```

```d
struct GfxEvent
{
    uint type;          // GFX_EV_*
    uint surface;       // the surface it is about, 0 if none
    int a, b, c, d;
    uint time;          // milliseconds since boot
    uint reserved;
}
```
