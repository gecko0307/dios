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
module ulib.dios.alloc;

import ulib.dios.sys;
import ulib.dios.mem;

/*
 * Heap allocator
 */

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

    Block* next = cast(Block*)(cast(ubyte*)(block + 1) + size);

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

extern(C):

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
