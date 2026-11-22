module dios.core.klog;

/**
 * Kernel log: a ring buffer that keeps the most recent text printed with
 * kprintf(), so boot messages and driver warnings can be read again after they
 * have scrolled off the screen (shell command `dmesg`). Output of the shell and
 * of user programs is not recorded.
 */
import dios.core.cpu;

enum size_t KLOG_SIZE = 32768;          // power of two

__gshared ubyte[KLOG_SIZE] klogBuf;
__gshared ulong klogTotal;              // bytes ever written; the newest KLOG_SIZE are kept

extern(C):

/// Append one character. Safe to call from interrupt handlers.
void klogPut(char c) @nogc nothrow
{
    ulong flags = cpuIrqSave();
    klogBuf[klogTotal & (KLOG_SIZE - 1)] = cast(ubyte)c;
    klogTotal++;
    cpuIrqRestore(flags);
}

/// Number of bytes currently held.
ulong klogLength() @nogc nothrow
{
    return klogTotal < KLOG_SIZE ? klogTotal : KLOG_SIZE;
}

/// Byte `index` of the held text, 0 being the oldest.
ubyte klogAt(ulong index) @nogc nothrow
{
    ulong start = klogTotal - klogLength();
    return klogBuf[(start + index) & (KLOG_SIZE - 1)];
}

/// True once old text has been overwritten.
bool klogWrapped() @nogc nothrow
{
    return klogTotal > KLOG_SIZE;
}
