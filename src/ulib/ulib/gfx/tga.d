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
module ulib.gfx.tga;

/**
 * TGA image decoder.
 */

import ulib.dios;
import ulib.gfx.image;

align(1) struct TGAHeader
{
   align(1):
    ubyte idLength;
    ubyte colmapType;
    ubyte encoding;
    ushort colmapStart;
    ushort colmapLen;
    ubyte colmapBits;
    ushort xstart;
    ushort ystart;
    ushort width;
    ushort height;
    ubyte bpp;
    ubyte descriptor;
}

enum TGAEncoding: ubyte
{
    NoData = 0,
    Indexed = 1,
    RGB = 2,
    Grey = 3,
    RLE_Indexed = 9,
    RLE_RGB = 10,
    RLE_Grey = 11
};

enum TGAOrigin: ubyte
{
    Left = 0x00,
    Right = 0x10,
    Lower = 0x00,
    Upper = 0x20
}

private bool readTGAHeader(const(ubyte)[] buffer, TGAHeader* outHdr) @nogc nothrow
{
    if (buffer.length < TGAHeader.sizeof)
        return false;
    
    memcpy(outHdr, buffer.ptr, TGAHeader.sizeof);
    
    version(Debug)
    {
        uprintf("idLength = %d\n", outHdr.idLength);
        uprintf("colmapType = %d\n", outHdr.colmapType);
        
        /*
         * Encoding flag:
         * 1 = Raw indexed image
         * 2 = Raw RGB
         * 3 = Raw greyscale
         * 9 = RLE indexed
         * 10 = RLE RGB
         * 11 = RLE greyscale
         * 32 & 33 = Other compression, indexed
         */
        uprintf("encoding = %d\n", outHdr.encoding);
        uprintf("colmapStart = %d\n", outHdr.colmapStart);
        uprintf("colmapLen = %d\n", outHdr.colmapLen);
        uprintf("colmapBits = %d\n", outHdr.colmapBits);
        uprintf("xstart = %d\n", outHdr.xstart);
        uprintf("ystart = %d\n", outHdr.ystart);
        uprintf("width = %d\n", outHdr.width);
        uprintf("height = %d\n", outHdr.height);
        uprintf("bpp = %d\n", outHdr.bpp);
        uprintf("descriptor = %d\n", outHdr.descriptor);
    }
    
    return true;
}

private bool readRawRGB(const(ubyte)[] input, const(TGAHeader)* hdr, ImageBGRA* outImg) @nogc nothrow
{
    if (hdr.bpp != 24 && hdr.bpp != 32)
    {
        uprintf("Error: unsupported bit depth %d (need 24 or 32)\n", hdr.bpp);
        return false;
    }

    size_t channels = hdr.bpp / 8;
    size_t w = hdr.width;
    size_t h = hdr.height;
    if (w == 0 || h == 0)
        return false;

    size_t inStride = w * channels;
    size_t outStride = w * 4;
    size_t rawImgSize = outStride * h;

    if (input.length < inStride * h)
    {
        uprintf("Error: pixel data is truncated\n");
        return false;
    }

    ubyte* buf = cast(ubyte*)umalloc(rawImgSize);
    if (buf is null)
        return false;

    outImg.width = hdr.width;
    outImg.height = hdr.height;
    outImg.data = buf[0..rawImgSize];

    bool fromTop = (hdr.descriptor & TGAOrigin.Upper) != 0;
    bool fromRight = (hdr.descriptor & TGAOrigin.Right) != 0;

    const(ubyte) alphaBits = cast(ubyte)(hdr.descriptor & 0xf);
    version(Debug)
        uprintf("Alpha bits: %d\n", alphaBits);
    // A 32 bpp file with 0 alpha bits has an unused 4th byte: treat it as opaque.
    bool hasAlpha = channels == 4 && alphaBits != 0;

    for (size_t y = 0; y < h; y++)
    {
        size_t yIn = fromTop ? y : (h - 1 - y);
        for (size_t x = 0; x < w; x++)
        {
            size_t xIn = fromRight ? (w - 1 - x) : x;
            const(ubyte)* s = input.ptr + yIn * inStride + xIn * channels;
            ubyte* d = buf + y * outStride + x * 4;

            d[0] = s[0]; // B
            d[1] = s[1]; // G
            d[2] = s[2]; // R
            d[3] = hasAlpha ? s[3] : 255;
        }
    }

    return true;
}

bool readRLERGB(const(ubyte)[] input, const(TGAHeader)* hdr, ImageBGRA* outImg) @nogc nothrow
{
    if (hdr.bpp != 24 && hdr.bpp != 32)
    {
        uprintf("Error: unsupported bit depth %d (need 24 or 32)\n", hdr.bpp);
        return false;
    }

    size_t channels = hdr.bpp / 8;
    size_t w = hdr.width;
    size_t h = hdr.height;

    if (w == 0 || h == 0)
        return false;

    size_t pixelCount = w * h;

    if (pixelCount > size_t.max / 4)
        return false;

    size_t rawImgSize = pixelCount * 4;

    ubyte* buf = cast(ubyte*)umalloc(rawImgSize);
    if (buf is null)
        return false;

    bool fromTop = (hdr.descriptor & TGAOrigin.Upper) != 0;
    bool fromRight = (hdr.descriptor & TGAOrigin.Right) != 0;

    const(ubyte) alphaBits = cast(ubyte)(hdr.descriptor & 0xf);
    bool hasAlpha = channels == 4 && alphaBits != 0;

    size_t inputPos = 0;
    size_t outputPos = 0;

    while (outputPos < pixelCount)
    {
        // Read packet header.
        if (inputPos >= input.length)
        {
            ufree(buf);
            return false;
        }

        ubyte packetHeader = input[inputPos++];

        bool isRLE = (packetHeader & 0x80) != 0;
        size_t packetCount = (packetHeader & 0x7f) + 1;

        // A packet must not exceed the remaining image pixels.
        if (packetCount > pixelCount - outputPos)
        {
            ufree(buf);
            return false;
        }

        if (isRLE)
        {
            // One pixel is repeated packetCount times.
            if (channels > input.length - inputPos)
            {
                ufree(buf);
                return false;
            }

            const(ubyte)* s = input.ptr + inputPos;
            inputPos += channels;

            for (size_t i = 0; i < packetCount; i++)
            {
                size_t index = outputPos + i;
                size_t x = index % w;
                size_t y = index / w;

                size_t dstX = fromRight ? w - 1 - x : x;
                size_t dstY = fromTop ? y : h - 1 - y;

                ubyte* d = buf + (dstY * w + dstX) * 4;

                d[0] = s[0]; // B
                d[1] = s[1]; // G
                d[2] = s[2]; // R
                d[3] = hasAlpha ? s[3] : 255;
            }
        }
        else
        {
            // Raw packet: read packetCount individual pixels.
            if (packetCount > (input.length - inputPos) / channels)
            {
                ufree(buf);
                return false;
            }

            for (size_t i = 0; i < packetCount; i++)
            {
                const(ubyte)* s = input.ptr + inputPos;
                inputPos += channels;

                size_t index = outputPos + i;
                size_t x = index % w;
                size_t y = index / w;

                size_t dstX = fromRight ? w - 1 - x : x;
                size_t dstY = fromTop ? y : h - 1 - y;

                ubyte* d = buf + (dstY * w + dstX) * 4;

                d[0] = s[0]; // B
                d[1] = s[1]; // G
                d[2] = s[2]; // R
                d[3] = hasAlpha ? s[3] : 255;
            }
        }

        outputPos += packetCount;
    }

    outImg.width = hdr.width;
    outImg.height = hdr.height;
    outImg.data = buf[0..rawImgSize];

    return true;
}

extern(C):

bool loadTGA(const(ubyte)[] input, ImageBGRA* img) @nogc nothrow
{
    size_t inputPos = 0;
    
    TGAHeader hdr;
    if (!readTGAHeader(input, &hdr))
    {
        uprintf("TGA error: failed to parse file header\n");
        return false;
    }
    
    inputPos += TGAHeader.sizeof;
    
    if (hdr.idLength > 0)
    {
        if (inputPos + hdr.idLength > input.length)
        {
            uprintf("TGA error: corrupted TGA header\n");
            return false;
        }

        // The ID field is not NUL-terminated in the file.
        char* id = cast(char*)umalloc(hdr.idLength + 1);
        if (id !is null)
        {
            memcpy(id, input.ptr + inputPos, hdr.idLength);
            id[hdr.idLength] = 0;
            version(Debug)
                uprintf("id = %s\n", id);
            ufree(id);
        }
        inputPos += hdr.idLength;
    }

    // The color map (if any) sits between the ID and the pixel data, even for RGB images.
    if (hdr.colmapType == 1)
        inputPos += cast(size_t)hdr.colmapLen * ((hdr.colmapBits + 7) / 8);

    if (inputPos > input.length)
    {
        uprintf("Error: corrupted TGA file\n");
        return false;
    }
    
    auto pixelData = input[inputPos..$];
    
    bool result = false;
    if (hdr.encoding == TGAEncoding.RGB)
        result = readRawRGB(pixelData, &hdr, img);
    else if (hdr.encoding == TGAEncoding.RLE_RGB)
        result = readRLERGB(pixelData, &hdr, img);
    else
    {
        uprintf("TGA error: only RGB images are supported\n");
        return false;
    }
    
    if (!result)
    {
        uprintf("TGA error: failed to decode image data\n");
        return false;
    }
    
    return true;
}
