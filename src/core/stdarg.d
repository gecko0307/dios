module core.stdarg;

alias void* va_list;

extern(C):

pragma(LDC_va_start) void va_start(T)(va_list ap, ref T) @nogc nothrow;
pragma(LDC_va_arg) T va_arg(T)(va_list ap) @nogc nothrow;
pragma(LDC_va_end) void va_end(va_list args) @nogc nothrow;
pragma(LDC_va_copy) void va_copy(va_list dst, va_list src) @nogc nothrow;
