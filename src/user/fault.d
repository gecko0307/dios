module fault;

import core.volatile;
import ulib;

// Deliberately crashes: the kernel must report it and keep running.
extern(C) int umain(const(char)* args) @nogc nothrow
{
    uputs("About to write to address 0...\n");
    volatileStore(cast(uint*)null, 1);
    uputs("not reached\n");
    return 0;
}
