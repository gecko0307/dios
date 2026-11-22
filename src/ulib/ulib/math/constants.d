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
module ulib.math.constants;

/**
 * Very small value
 */
enum EPSILON = 0.000001;

/*
 * Basic math constants
 */
enum double E           = 2.7182818284590452;
enum double PI          = 3.1415926535897932;
enum double HALFPI      = 1.5707963267948966; // PI/2
enum double QUARTPI     = 0.7853981633974483; // PI/4
enum double INVPI       = 0.3183098861837907; // 1/PI
enum double INVTWOPI    = 0.1591549430918953; // 1/2PI
enum double TWOPI       = 6.2831853071795865; // 2PI
enum double THREEHALFPI = 4.7123889803846899; // 3PI/2
enum double LN10        = 2.3025850929940457; // ln(10)
enum double LN2         = 0.6931471805599453; // ln(2)
enum double INVLN2      = 1.4426950408889634; // 1/ln(2)
enum double LOG2        = 0.3010299956639812; // log10(2)
enum double LOG2E       = 1.4426950408889634; // log2(e)
enum double LOG10E      = 0.4342944819032518; // log10(E)
enum double LOG2T       = 3.3219280948873623; // log2(10)
enum double SQRT2       = 1.4142135623730951; // sqrt(2)
enum double SQRT1_2     = 0.7071067811865476; // sqrt(1/2)

// std.math compatibility
alias PI_2 = HALFPI;
alias PI_4 = QUARTPI;
alias M_1_PI = INVPI;
enum double M_2_PI      = 0.6366197723675813; // 2/PI
enum double M_2_SQRTPI  = 1.1283791670955125; // 2/sqrt(PI)
