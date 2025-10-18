module error;

import stdio;

extern(C):

// Halt and catch fire
void hcf() @nogc nothrow
{
    for (;;) asm @nogc nothrow
    {
        hlt;
    }
}

void kPanic(string message = "") @nogc nothrow
{
    kprintf(message);
    for (;;) asm @nogc nothrow
    {
        hlt;
    }
}

void kAssert(bool condition, string failMessage = "") @nogc nothrow
{
    if(!condition)
        kPanic(failMessage);
}
