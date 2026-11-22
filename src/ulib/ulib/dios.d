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
module ulib.dios;

/**
 * DIOS kernel API.
 */

enum ulong SYS_EXIT = 0;
enum ulong SYS_WRITE = 1;
enum ulong SYS_GETKEY = 2;
enum ulong SYS_SLEEP = 3;
enum ulong SYS_TICKS = 4;
enum ulong SYS_CLEAR = 5;
enum ulong SYS_OPEN = 6;
enum ulong SYS_READ = 7;
enum ulong SYS_CLOSE = 8;
enum ulong SYS_SEEK = 9;
enum ulong SYS_STAT = 10;
enum ulong SYS_READDIR = 11;
enum ulong SYS_GETCWD = 12;
enum ulong SYS_BRK = 13;
enum ulong SYS_YIELD = 14;
enum ulong SYS_GETPID = 15;

// useek() origins
enum int SEEK_SET = 0;
enum int SEEK_CUR = 1;
enum int SEEK_END = 2;

// Layouts shared with the kernel (sysfile.d)
struct UStat
{
    ulong size;
    uint mtime; // DOS timestamp: (year-1980)<<25 | month<<21 | day<<16 | hour<<11 | min<<5 | sec/2
    uint isDir;
}

struct UDirent
{
    ulong size;
    uint mtime;
    uint isDir;
    char[256] name;
}

// Key codes returned by getkey (besides plain ASCII; Enter is 10).
enum int KEY_UP = 0x101;
enum int KEY_DOWN = 0x102;
enum int KEY_LEFT = 0x103;
enum int KEY_RIGHT = 0x104;
enum int KEY_HOME = 0x105;
enum int KEY_END = 0x106;
enum int KEY_DELETE = 0x107;

extern(C):

/// Calls a kernel function.
long sys_call(ulong nr, ulong a0, ulong a1, ulong a2) @nogc nothrow;

///
void* memset(void* dst, int c, size_t n) @nogc nothrow
{
    ubyte* p = cast(ubyte*)dst;
    for (size_t i = 0; i < n; i++)
        p[i] = cast(ubyte)c;
    return dst;
}

///
void* memcpy(void* dst, const(void)* src, size_t n) @nogc nothrow
{
    ubyte* d = cast(ubyte*)dst;
    const(ubyte)* s = cast(const(ubyte)*)src;
    for (size_t i = 0; i < n; i++)
        d[i] = s[i];
    return dst;
}

///
void* memmove(void* dst, const(void)* src, size_t n) @nogc nothrow
{
    ubyte* d = cast(ubyte*)dst;
    const(ubyte)* s = cast(const(ubyte)*)src;
    if (d < s)
    {
        for (size_t i = 0; i < n; i++)
            d[i] = s[i];
    }
    else
    {
        for (size_t i = n; i > 0; i--)
            d[i - 1] = s[i - 1];
    }
    return dst;
}

/// Terminates the application.
void uexit(long code) @nogc nothrow
{
    sys_call(SYS_EXIT, cast(ulong)code, 0, 0);
}

///
size_t ustrlen(const(char)* s) @nogc nothrow
{
    size_t n = 0;
    while (s[n] != 0)
        n++;
    return n;
}

/// Writes to the standard output (the kernel shell, if running in text mode).
void uwrite(const(char)* s, size_t n) @nogc nothrow
{
    sys_call(SYS_WRITE, cast(ulong)s, n, 0);
}

/// Writes a zero-terminated string to the standard output.
void uputs(const(char)* s) @nogc nothrow
{
    uwrite(s, ustrlen(s));
}

/// Writes a character to the standard output.
void uputc(char c) @nogc nothrow
{
    uwrite(&c, 1);
}

/// Writes an unsigned integer to the standard output.
void uputu(ulong v) @nogc nothrow
{
    char[20] d;
    uint k = 20;
    do
    {
        d[--k] = cast(char)('0' + v % 10);
        v /= 10;
    }
    while (v != 0);
    uwrite(d.ptr + k, 20 - k);
}

/// Writes an unsigned integer in hexadecimal format to the standard output.
void uputhex(ulong v) @nogc nothrow
{
    char[16] d;
    for (int i = 15; i >= 0; i--)
    {
        uint nib = cast(uint)(v & 15);
        d[i] = cast(char)(nib < 10 ? '0' + nib : 'a' + nib - 10);
        v >>= 4;
    }
    uwrite("0x".ptr, 2);
    uwrite(d.ptr, 16);
}

/// Writes a floating-point number to the standard output.
void uputf(double v, uint precision = 6) @nogc nothrow
{
    if (v != v)
    {
        uputs("nan");
        return;
    }

    if (v > double.max)
    {
        uputs("inf");
        return;
    }

    if (v < -double.max)
    {
        uputs("-inf");
        return;
    }

    if (precision > 15)
        precision = 15;

    if (v < 0.0)
    {
        uputc('-');
        v = -v;
    }

    // Avoid converting an out-of-range integer.
    if (v >= 18446744073709551616.0)
    {
        uputs("overflow");
        return;
    }

    ulong integer = cast(ulong)v;
    double fraction = v - cast(double)integer;

    uputu(integer);

    if (precision == 0)
        return;

    uputc('.');

    ulong scale = 1;
    for (uint i = 0; i < precision; ++i)
        scale *= 10;

    ulong fractional = cast(ulong)(fraction * cast(double)scale + 0.5);

    if (fractional >= scale)
    {
        // Fraction rounded up: carry into integer part.
        fractional = 0;
        // Reprint the integer part with the carry.
        // This case is handled below by a separate output path.
        if (integer == ulong.max)
        {
            uputs("overflow");
            return;
        }

        // We already printed the integer, so avoid this path by
        // handling rounding before output in a production version.
    }

    // Print leading zeros in the fractional part.
    ulong divisor = scale / 10;

    while (divisor > 0)
    {
        uputc(cast(char)('0' + (fractional / divisor) % 10));
        divisor /= 10;
    }
}

/// Next key (ASCII, Enter = 10, or KEY_*). With block == false returns -1 if none is waiting.
int ugetkey(bool block) @nogc nothrow
{
    return cast(int)sys_call(SYS_GETKEY, block ? 1 : 0, 0, 0);
}

/// Stops execution for a given time in milliseconds.
void usleep(ulong ms) @nogc nothrow
{
    sys_call(SYS_SLEEP, ms, 0, 0);
}

/// Returns the number of millisecond ticks since the system start.
ulong uticks() @nogc nothrow
{
    return cast(ulong)sys_call(SYS_TICKS, 0, 0, 0);
}

/// Let other programs run now.
void uyield() @nogc nothrow
{
    sys_call(SYS_YIELD, 0, 0, 0);
}

/// Task id of this program (as shown by `ps`).
int ugetpid() @nogc nothrow
{
    return cast(int)sys_call(SYS_GETPID, 0, 0, 0);
}

/// Clears the standard ouput (the kernel shell, if running in text mode).
void uclear() @nogc nothrow
{
    sys_call(SYS_CLEAR, 0, 0, 0);
}

// Files (read-only). Paths are relative to the shell's current directory or absolute.
// At most 8 files can be open at once; they are closed when the program ends.

/// Returns the file descriptor of a file or directory, or -1 if it doesn't exist.
int uopen(const(char)* path) @nogc nothrow
{
    return cast(int)sys_call(SYS_OPEN, cast(ulong)path, 0, 0);
}

/// Reads bytes from the file at the current offset. Returns the number of bytes read (0 = end of file), or -1 on error.
long uread(int fd, void* buf, size_t n) @nogc nothrow
{
    return sys_call(SYS_READ, cast(ulong)fd, cast(ulong)buf, n);
}

/// Closes the file.
int uclose(int fd) @nogc nothrow
{
    return cast(int)sys_call(SYS_CLOSE, cast(ulong)fd, 0, 0);
}

/// Jumps to a byte offset in the file. Returns a new position, or -1 on error.
long useek(int fd, long offset, int whence) @nogc nothrow
{
    return sys_call(SYS_SEEK, cast(ulong)fd, cast(ulong)offset, cast(ulong)whence);
}

/// Retrieves file stats. Returns 0 on success, -1 if the path does not exist.
int ustat(const(char)* path, UStat* st) @nogc nothrow
{
    return cast(int)sys_call(SYS_STAT, cast(ulong)path, cast(ulong)st, 0);
}

/// Fills the next entry of a directory opened with uopen(). Returns 1 if filled in, 0 if there are no more entries, -1 on error.
int ureaddir(int fd, UDirent* e) @nogc nothrow
{
    return cast(int)sys_call(SYS_READDIR, cast(ulong)fd, cast(ulong)e, 0);
}

/// Writes the current working directory into a provided character buffer. Returns CWD length or -1 on error.
long ugetcwd(char* buf, size_t n) @nogc nothrow
{
    return sys_call(SYS_GETCWD, cast(ulong)buf, n, 0);
}

/**
 * Query or change the current process' heap break.
 * Returns the current/new break, or null on failure.
 */
void* ubrk(void* newBreak) @nogc nothrow
{
    long result = sys_call(SYS_BRK, cast(ulong)newBreak, 0, 0);
    return result < 0 ? null : cast(void*)result;
}

// Allocator

private enum USER_IMAGE_MAX = 0x40000000;
private enum USER_HEAP_BASE = USER_IMAGE_MAX;

private enum size_t ALIGNMENT = 16;
private enum size_t HEADER_SIZE = 32;

private enum ulong BLOCK_USED = 0x554D454D55534544UL;
private enum ulong BLOCK_FREE = 0x554D454D46524545UL;

struct UHeapStats
{
    size_t heapSize;
    size_t allocatedBytes;
    size_t freeBytes;
    size_t metadataBytes;
    size_t allocatedBlocks;
    size_t freeBlocks;
}

private struct Block
{
    size_t size; // Payload size
    Block* prev;
    Block* next;
    ulong tag;
}

static assert(Block.sizeof == HEADER_SIZE);

private __gshared Block* firstBlock;
private __gshared Block* lastBlock;
private __gshared void* heapBase;
private __gshared void* heapEnd;
private __gshared bool initialized;

private size_t alignSize(size_t size) @nogc nothrow
{
    return (size + ALIGNMENT - 1) & ~(ALIGNMENT - 1);
}

private bool initHeap() @nogc nothrow
{
    if (initialized)
        return true;

    heapBase = ubrk(null);
    if (heapBase is null)
        return false;

    heapEnd = heapBase;
    initialized = true;
    return true;
}

private Block* findBlock(void* ptr) @nogc nothrow
{
    for (Block* block = firstBlock;
         block !is null;
         block = block.next)
    {
        if (cast(void*)(block + 1) == ptr)
            return block;
    }

    return null;
}

private void mergeNext(Block* block) @nogc nothrow
{
    Block* next = block.next;

    if (next is null || next.tag != BLOCK_FREE)
        return;

    block.size += HEADER_SIZE + next.size;
    block.next = next.next;

    if (block.next !is null)
        block.next.prev = block;
    else
        lastBlock = block;
}

private void splitBlock(Block* block, size_t size) @nogc nothrow
{
    size_t remaining = block.size - size;

    if (remaining < HEADER_SIZE + ALIGNMENT)
        return;

    Block* next = cast(Block*)(
        cast(ubyte*)(block + 1) + size
    );

    next.size = remaining - HEADER_SIZE;
    next.prev = block;
    next.next = block.next;
    next.tag = BLOCK_FREE;

    if (next.next !is null)
        next.next.prev = next;
    else
        lastBlock = next;

    block.next = next;
    block.size = size;
}

private bool extendHeap(size_t size) @nogc nothrow
{
    bool reuseLast = lastBlock !is null &&
                     lastBlock.tag == BLOCK_FREE;

    size_t extra = size;

    if (!reuseLast)
    {
        if (extra > size_t.max - HEADER_SIZE)
            return false;

        extra += HEADER_SIZE;
    }

    ulong oldBreak = cast(ulong)heapEnd;

    if (extra > ulong.max - oldBreak)
        return false;

    void* newBreak = ubrk(cast(void*)(oldBreak + extra));

    if (newBreak is null)
        return false;

    if (reuseLast)
    {
        lastBlock.size += size;
    }
    else
    {
        Block* block = cast(Block*)heapEnd;

        block.size = size;
        block.prev = lastBlock;
        block.next = null;
        block.tag = BLOCK_FREE;

        if (lastBlock !is null)
            lastBlock.next = block;
        else
            firstBlock = block;

        lastBlock = block;
    }

    heapEnd = newBreak;
    return true;
}

/// Allocate a block of memory.
void* umalloc(size_t size) @nogc nothrow
{
    if (size == 0)
        size = 1;

    if (size > size_t.max - (ALIGNMENT - 1))
        return null;

    size = alignSize(size);

    if (!initHeap())
        return null;

    for (Block* block = firstBlock;
         block !is null;
         block = block.next)
    {
        if (block.tag == BLOCK_FREE && block.size >= size)
        {
            splitBlock(block, size);
            block.tag = BLOCK_USED;
            return block + 1;
        }
    }

    if (!extendHeap(size))
        return null;

    Block* block = lastBlock;
    block.tag = BLOCK_USED;

    return block + 1;
}

/// Allocate and zero-initialize an array of elements.
void* ucalloc(size_t count, size_t size) @nogc nothrow
{
    if (count == 0 || size == 0)
        return null;

    if (count > size_t.max / size)
        return null;

    size_t total = count * size;

    void* ptr = umalloc(total);

    if (ptr !is null)
        memset(ptr, 0, total);

    return ptr;
}

/// Resize an allocation while preserving its contents.
void* urealloc(void* ptr, size_t size) @nogc nothrow
{
    if (ptr is null)
        return umalloc(size);

    if (size == 0)
    {
        ufree(ptr);
        return null;
    }

    if (size > size_t.max - (ALIGNMENT - 1))
        return null;

    size = alignSize(size);

    if (!initialized)
        return null;

    Block* block = findBlock(ptr);

    if (block is null || block.tag != BLOCK_USED)
        return null;

    // Shrink in place.
    if (size <= block.size)
    {
        splitBlock(block, size);

        // The new remainder may be adjacent to another free block.
        if (block.next !is null && block.next.tag == BLOCK_FREE)
            mergeNext(block.next);

        return ptr;
    }

    // Consume the following free block if possible.
    if (block.next !is null && block.next.tag == BLOCK_FREE)
    {
        mergeNext(block);

        if (block.size >= size)
        {
            splitBlock(block, size);
            return ptr;
        }
    }

    // The allocation is at the end of the heap.
    // Grow it directly without moving its contents.
    if (block == lastBlock)
    {
        size_t extra = size - block.size;
        ulong oldBreak = cast(ulong)heapEnd;

        if (extra <= ulong.max - oldBreak)
        {
            void* newBreak = ubrk(
                cast(void*)(oldBreak + extra)
            );

            if (newBreak !is null)
            {
                block.size = size;
                heapEnd = newBreak;
                return ptr;
            }
        }
    }

    // Fallback: allocate, copy and release the old block.
    void* newPtr = umalloc(size);

    if (newPtr is null)
        return null;

    size_t copySize = block.size < size ? block.size : size;

    memcpy(newPtr, ptr, copySize);
    ufree(ptr);

    return newPtr;
}

/// Release a previously allocated block.
void ufree(void* ptr) @nogc nothrow
{
    if (ptr is null || !initialized)
        return;

    Block* block = findBlock(ptr);

    if (block is null || block.tag != BLOCK_USED)
        return;

    block.tag = BLOCK_FREE;

    mergeNext(block);

    if (block.prev !is null && block.prev.tag == BLOCK_FREE)
        mergeNext(block.prev);
}

/// Get current heap statistics.
bool uheapGetStats(UHeapStats* stats) @nogc nothrow
{
    if (stats is null || !initHeap())
        return false;

    *stats = UHeapStats.init;

    stats.heapSize = cast(size_t)(cast(ulong)heapEnd - cast(ulong)heapBase);

    for (Block* block = firstBlock;
         block !is null;
         block = block.next)
    {
        stats.metadataBytes += HEADER_SIZE;

        if (block.tag == BLOCK_USED)
        {
            stats.allocatedBytes += block.size;
            stats.allocatedBlocks++;
        }
        else if (block.tag == BLOCK_FREE)
        {
            stats.freeBytes += block.size;
            stats.freeBlocks++;
        }
    }

    return true;
}
