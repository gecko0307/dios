module dios.core.cpu;

// Thin D bindings for cpu.s.

extern(C):

void gdtFlush(const(void)* gdtr) @nogc nothrow;
void idtLoad(const(void)* idtr) @nogc nothrow;
void tssLoad(ushort selector) @nogc nothrow;

ulong cpuReadMsr(uint msr) @nogc nothrow;
void cpuWriteMsr(uint msr, ulong value) @nogc nothrow;
void cpuCpuid(uint leaf, uint subleaf, uint* outEaxEbxEcxEdx) @nogc nothrow;
ulong cpuReadCr2() @nogc nothrow;

/// Disable interrupts and return the previous RFLAGS. Pair with cpuIrqRestore.
ulong cpuIrqSave() @nogc nothrow;
/// Re-enable interrupts if (and only if) they were enabled in `flags`.
void cpuIrqRestore(ulong flags) @nogc nothrow;
void cpuSti() @nogc nothrow;
void cpuCli() @nogc nothrow;
/// STI;HLT - sleep until the next interrupt (leaves interrupts enabled).
void cpuHlt() @nogc nothrow;
/// Reset the machine by deliberately triple-faulting. Does not return.
void cpuTripleFault() @nogc nothrow;

void* isrStubAddress(uint vector) @nogc nothrow;

enum uint MSR_APIC_BASE = 0x1B;

/// CPUID leaf 1, EDX/ECX feature tests
bool cpuHasApic() @nogc nothrow
{
    uint[4] r;
    cpuCpuid(1, 0, r.ptr);
    return (r[3] & (1u << 9)) != 0;
}

bool cpuHasX2Apic() @nogc nothrow
{
    uint[4] r;
    cpuCpuid(1, 0, r.ptr);
    return (r[2] & (1u << 21)) != 0;
}
