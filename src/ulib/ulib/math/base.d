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

/**
 * Elementary math functions.
 */
module ulib.math.base;

import ulib.core.traits;
import ulib.math.constants;

private template SignLayout(T)
{
    static if (T.mant_dig == 24) // IEEE binary32
    {
        alias Word = uint;
        enum size_t index = 0;
        enum Word mask = 0x8000_0000;
    }
    else static if (T.mant_dig == 53) // IEEE binary64
    {
        alias Word = ulong;
        enum size_t index = 0;
        enum Word mask = 0x8000_0000_0000_0000;
    }
    else static if (T.mant_dig == 64) // x87 80-bit extended (always little-endian)
    {
        alias Word = ushort; // sign lives in the top bit of bytes 8..9
        enum size_t index = 4;
        enum Word mask = 0x8000;
    }
    else static if (T.mant_dig == 113) // IEEE binary128
    {
        alias Word = ushort;
        version (LittleEndian) enum size_t index = 7;
        else                   enum size_t index = 0;
        enum Word mask = 0x8000;
    }
    else
        static assert(0, "copysign: unsupported floating-point format " ~ T.stringof);
}

private union Bits(T)
{
    T value;
    SignLayout!T.Word[T.sizeof / SignLayout!T.Word.sizeof] word;
}

pragma(inline, true)
bool signbit(T)(T x) pure nothrow @nogc
    if (isFloatingPoint!T)
{
    if (__ctfe)
        // NaN sign isn't observable at CTFE
        return x < 0 || (x == 0 && 1 / x < 0);

    alias L = SignLayout!T;
    Bits!T b;
    b.value = x;
    return (b.word[L.index] & L.mask) != 0;
}

T copysign(T, R)(T mag, R sgn) pure nothrow @nogc
    if (isFloatingPoint!T && isFloatingPoint!R)
{
    immutable(bool) neg = signbit(sgn);

    if (__ctfe)
        return signbit(mag) == neg ? mag : -mag;

    alias L = SignLayout!T;
    Bits!T b;
    b.value = mag;
    if (neg)
        b.word[L.index] |= L.mask;
    else
        b.word[L.index] &= cast(L.Word) ~L.mask;
    return b.value;
}

pragma(inline, true)
T abs(T)(T v) pure nothrow @nogc
{
    return (v > 0.0)? v : -v;
}

T fabs(T)(T x) pure nothrow @nogc
    if (isFloatingPoint!T)
{
    if (__ctfe)
        return signbit(x) ? -x : x;
    alias L = SignLayout!T;
    Bits!T b;
    b.value = x;
    b.word[L.index] &= cast(L.Word) ~L.mask;
    return b.value;
}

T fmax(T)(T x, T y) pure nothrow @nogc
    if (isFloatingPoint!T)
{
    if (x != x) return y;
    if (y != y) return x;
    if (x == y) return signbit(x) ? y : x;
    return x > y ? x : y;
}

T fmin(T)(T x, T y) pure nothrow @nogc
    if (isFloatingPoint!T)
{
    if (x != x) return y;
    if (y != y) return x;
    if (x == y) return signbit(x) ? x : y;
    return x < y ? x : y;
}

// Current rounding mode (round-half-even by default).
T rint(T)(T x) pure nothrow @nogc
    if (isFloatingPoint!T)
{
    enum T M = 1 / T.epsilon;
    if (!(fabs(x) < M)) return x;
    T r = (x >= 0) ? (x + M) - M : (x - M) + M;   // signed, so directed modes work
    return copysign(r, x);            // keeps -0.0
}

// x = n*pi/2 + (y0 + y1), |y0| <= pi/4. Returns n mod 4.
// Accurate for |x| < 2^20 * pi/2 (~1.6e6); beyond that you need Payne-Hanek.
private int reducePio2(double x, out double y0, out double y1) pure nothrow @nogc
{
    enum double invpio2 = 6.36619772367581382433e-01,
                pio2_1  = 1.57079632673412561417e+00,   // first 33 bits of pi/2
                pio2_2  = 6.07710050630396597660e-11,   // next 33 bits
                pio2_2t = 2.02226624879595063154e-21,
                pio2_3  = 2.02226624871116645580e-21,   // next 33 bits
                pio2_3t = 8.47842766036889956997e-32;

    immutable double fn = rint(x * invpio2);
    double r = x - fn * pio2_1; // exact
    double t = r;
    double w = fn * pio2_2;
    r = t - w;
    w = fn * pio2_2t - ((t - r) - w);
    t = r;
    w = fn * pio2_3;
    r = t - w;
    w = fn * pio2_3t - ((t - r) - w);
    y0 = r - w;
    y1 = (r - y0) - w;
    return cast(int)(cast(long) fn & 3);
}

// sin(x + y) for |x| <= pi/4; y is a tiny correction term (the tail of the reduced argument)
pragma(inline, true)
private double sinKernel(double x, double y) pure nothrow @nogc
{
    enum double S1 = -1.66666666666666324348e-01, S2 =  8.33333333332248946124e-03,
                S3 = -1.98412698298579493134e-04, S4 =  2.75573137070700676789e-06,
                S5 = -2.50507602534068634195e-08, S6 =  1.58969099521155010221e-10;
    immutable double z = x * x;
    immutable double v = z * x;
    immutable double r = S2 + z * (S3 + z * (S4 + z * (S5 + z * S6)));
    return x - ((z * (0.5 * y - v * r) - y) - v * S1);
}

pragma(inline, true)
private double cosKernel(double x, double y) pure nothrow @nogc
{
    enum double C1 =  4.16666666666666019037e-02, C2 = -1.38888888888741095749e-03,
                C3 =  2.48015872894767294178e-05, C4 = -2.75573143513906633035e-07,
                C5 =  2.08757232129817482790e-09, C6 = -1.13596475577881948265e-11;
    immutable double z  = x * x;
    immutable double r  = z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * C6)))));
    immutable double hz = 0.5 * z;
    immutable double w  = 1.0 - hz;
    return w + (((1.0 - w) - hz) + (z * r - x * y));
}

T sin(T)(T x) pure nothrow @nogc
    if (isFloatingPoint!T)
{
    double xd = x;
    double ax = fabs(xd);

    if (ax < 0x1p-27)
        return cast(T)xd; // +-0 (sign kept) and tiny x
    if (!(ax < double.infinity))
        return cast(T)(xd - xd); // NaN, +-inf -> NaN

    double y0, y1;
    switch (reducePio2(xd, y0, y1))
    {
        case 0:  return cast(T)  sinKernel(y0, y1);
        case 1:  return cast(T)  cosKernel(y0, y1);
        case 2:  return cast(T) -sinKernel(y0, y1);
        default: return cast(T) -cosKernel(y0, y1);
    }
}

T cos(T)(T x) pure nothrow @nogc
    if (isFloatingPoint!T)
{
    double xd = x;
    double ax = fabs(xd);

    if (ax < 0x1p-27)
        return 1;
    if (!(ax < double.infinity))
        return cast(T)(xd - xd); // NaN, +-inf -> NaN

    double y0, y1;
    switch (reducePio2(xd, y0, y1))
    {
        case 0:  return cast(T)  cosKernel(y0, y1);
        case 1:  return cast(T) -sinKernel(y0, y1);
        case 2:  return cast(T) -cosKernel(y0, y1);
        default: return cast(T)  sinKernel(y0, y1);
    }
}
