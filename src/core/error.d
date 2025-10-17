module core.error;

import core.stdio;

extern(C):

void kAssert(bool condition, string failMessage = "") @nogc nothrow
{
    if(!condition)
        kPanic(failMessage);
}

void kPanic(string message = "") @nogc nothrow
{
    kprintf(message);
    for(;;) { }
}
