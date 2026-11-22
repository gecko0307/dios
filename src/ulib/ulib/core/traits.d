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
module ulib.core.traits;

///
template Unqual(T: const U, U)
{
    alias Unqual = U;
}

///
template isInteger(T)
{
    enum isInteger = is(Unqual!T == int) || is(Unqual!T == uint) ||
                     is(Unqual!T == byte) || is(Unqual!T == ubyte) ||
                     is(Unqual!T == short) || is(Unqual!T == ushort) ||
                     is(Unqual!T == long) || is(Unqual!T == ulong);
}

///
template isFloatingPoint(T)
{
    enum isFloatingPoint = is(Unqual!T == float) || is(Unqual!T == double) || is(Unqual!T == real);
}

///
template isSingleFloat(T)
{
    enum isSingleFloat = is(Unqual!T == float);
}

///
template isStaticArray(T)
{
    enum isStaticArray = is(T == U[N], U, size_t N);
}

///
template isDynamicArray(T)
{
    enum isDynamicArray = is(T == U[], U);
}

///
template isArray(T)
{
    enum isArray = isDynamicArray!T || isStaticArray!T;
}

///
template isString(T)
{
    enum isString = is(T == string) || is(T == char[]) || is(T: const(char)[]);
}

///
template isWString(T)
{
    enum isWString = is(T == wstring) || is(T == wchar[]) || is(T == const(wchar)[]);
}

///
template ElementType(T)
{
    static if (is(T == U[], U))
        alias ElementType = U;
}

///
template isPointer(T)
{
    enum isPointer = is(T: const(void)*);
}

///
template isClass(T)
{
    enum isClass = is(T == class);
}

///
template isInterface(T)
{
    enum isInterface = is(T == interface);
}

///
template isObject(T)
{
    enum isObject = isClass!T || isInterface!T;
}

///
template hasConstructor(T)
{
    enum hasConstructor = __traits(hasMember, T, "__ctor");
}

///
template hasDestructor(T)
{
    enum hasDestructor = __traits(hasMember, T, "__dtor");
}

///
template isFinalizable(T)
{
    enum isFinalizable =
        is(T == class) ||
        is(T == interface) ||
        hasDestructor!T ||
        isDynamicArray!T;
}

///
template isConvertibleToString(T)
{
    enum isConvertibleToString =
        __traits(hasMember, T, "toString") && is(typeof(T.init.toString()): const(char)[]);
}
