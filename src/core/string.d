module core.string;

private import core.stddef;

extern(C):

void* kmemchr(void* src, int c, size_t size) @nogc nothrow
{
    char* pcSrc = cast(char*)src;
    while(--size)
    {
        if(c == *pcSrc)
        {
            return cast(void*)pcSrc;
        }
        else
        {
               pcSrc++;
        }
    }
    return null;
}

int kmemcmp(void* dst, void* src, size_t size) @nogc nothrow
{
    size_t* plDst = cast(size_t*) dst;
    size_t* plSrc = cast(size_t*) src;
    if(!(cast(size_t)src & 0xFFFFFFFC) && !(cast(size_t)dst & 0xFFFFFFFC))
    {
        while(size >= 4)
        {
            if(*plDst++ == *plSrc++)
            {
                size -= 4;
            }
            else
            {
                return 0;
            }
        }
    }
    char* pcDst = cast(char*) plDst;
    char* pcSrc = cast(char*) plSrc;
    while(--size)
    {
        if(*pcDst++ != *pcSrc++)
        {
            return 0;
        }
    }
    return 1;
}

void* kmemcpy(void* dst, void* src, size_t size) @nogc nothrow
{
    size_t* plDst = cast(size_t*) dst;
    size_t* plSrc = cast(size_t*) src;
    if(!(cast(size_t)src & 0xFFFFFFFC) && !(cast(size_t)dst & 0xFFFFFFFC))
    {
        while(size >= 4)
        {
            *plDst++ = *plSrc++;
            size -= 4;
        }
    }
    char* pcDst = cast(char*) plDst;
    char* pcSrc = cast(char*) plSrc;
    while(--size)
    {
        *pcDst++ = *pcSrc++;
    }
    return dst;
}

void* kmemmove(void* dst, void* src, size_t size) @nogc nothrow
{
    size_t* plDst = cast(size_t*) dst;
    size_t* plSrc = cast(size_t*) src;
    
    if (plSrc < plDst && plDst < plSrc + size) 
    {
        plSrc += size;
        plDst += size;
        if(!(cast(size_t)src & 0xFFFFFFFC) && !(cast(size_t)dst & 0xFFFFFFFC))
        {
            while(size >= 4)
            {
                *--plDst = *--plSrc;
                size -= 4;
            }
        }
        char* pcDst = cast(char*) plDst;
        char* pcSrc = cast(char*) plSrc;
        while(--size)
        {
            *--pcDst = *--pcSrc;
        }
        return dst;
    }
    else
    {
        if(!(cast(size_t)src & 0xFFFFFFFC) && !(cast(size_t)dst & 0xFFFFFFFC))
        {
            while(size >= 4)
            {
                *plDst++ = *plSrc++;
                size -= 4;
            }
        }
        char* pcDst = cast(char*) plDst;
        char* pcSrc = cast(char*) plSrc;
        while(--size)
        {
            *pcDst++ = *pcSrc++;
        }
        return dst;
    }
}

void* kmemset(void* dst, int c, size_t size) @nogc nothrow
{
    char* pcDst = cast(char*)dst;
    while(--size)
    {
        *pcDst++ = cast(char)c;
    }
    return dst;
}

void* memset(void* dst, int c, size_t size) @nogc nothrow
{
    char* pcDst = cast(char*)dst;
    while(--size)
    {
        *pcDst++ = cast(char)c;
    }
    return dst;
}

char* kstrcpy(char* s1, char* s2) @nogc nothrow
{
    char *dst = s1;
    char *src = s2;
    while ((*dst++ = *src++) != '\0') { }
    return s1;
}

char* kstrncpy(char* s1, char* s2, size_t n) @nogc nothrow
{
    char *dst = s1;
    char *src = s2;
    while (n > 0) 
    {
        n--;
        if ((*dst++ = *src++) == '\0') 
        {
            kmemset(dst, '\0', n);
            break;
        }
    }
    return s1;
}

char* kstrcat(char* s1, char* s2) @nogc nothrow
{
    char *s = s1;
    while (*s != '\0')
        s++;
    kstrcpy(s, s2);
    return s1;
}

char* kstrncat(char* s1, char* s2, size_t n) @nogc nothrow
{
    char *s = s1;
    while (*s != '\0') s++;
    while (n != 0 && (*s = *s2++) != '\0') 
    {
        n--;
        s++;
    }
    if (*s != '\0')
        *s = '\0';
    return s1;
}

int kstrcmp(char* s1, char* s2) @nogc nothrow
{
    char uc1, uc2;
    while (*s1 != '\0' && *s1 == *s2) 
    {
        s1++;
        s2++;
    }
    uc1 =  *s1;
    uc2 =  *s2;
    return ((uc1 < uc2) ? -1 : (uc1 > uc2));
}

int kstrncmp(char* s1, char* s2, size_t n) @nogc nothrow
{
    char uc1, uc2;
    if (n == 0)
        return 0;
    while (n-- > 0 && *s1 == *s2) {
        if (n == 0 || *s1 == '\0')
            return 0;
        s1++;
        s2++;
    }
    uc1 =  *s1;
    uc2 =  *s2;
    return ((uc1 < uc2) ? -1 : (uc1 > uc2));
}

char* kstrchr(char* s, int c) @nogc nothrow
{
    while (*s != '\0' && *s != c)
        s++;
    return ( (*s == c) ? cast(char *) s : null );
}

size_t kstrcspn(char* s1, char* s2) @nogc nothrow
{
    char *sc1;
    for (sc1 = s1; *sc1 != '\0'; sc1++)
        if (kstrchr(s2, *sc1) != null)
            return (sc1 - s1);
    return sc1 - s1;
}

char* kstrpbrk(char* s1, char* s2) @nogc nothrow
{
    char *sc1;
    for (sc1 = s1; *sc1 != '\0'; sc1++)
        if (kstrchr(s2, *sc1) != null)
            return cast(char *)sc1;
    return null;
}

char* kstrrchr(char* s, int c) @nogc nothrow
{
    char *last = null;
    if (c == '\0')
        return kstrchr(s, c);
    while ((s = kstrchr(s, c)) != null) 
    {
        last = s;
        s++;
    }
    return cast(char *) last;
}

size_t kstrspn(char* s1, char* s2) @nogc nothrow
{
    char *sc1;
    for (sc1 = s1; *sc1 != '\0'; sc1++)
        if (kstrchr(s2, *sc1) == null)
            return (sc1 - s1);
    return sc1 - s1;
}

char* kstrstr(char* s1, char* s2) @nogc nothrow
{
    size_t s2len;
    if (*s2 == '\0')
        return cast(char *) s1;
    s2len = kstrlen(s2);
    for (; (s1 = kstrchr(s1, *s2)) != null; s1++)
        if (kstrncmp(s1, s2, s2len) == 0)
            return cast(char *) s1;
    return null;
}

char* kstrtok_r(char* s1, char* s2, char** lasts) @nogc nothrow
{
    char *sbegin;
    char *send;
    sbegin = s1 ? s1 : *lasts;
    sbegin += kstrspn(sbegin, s2);
    if (*sbegin == '\0') {
        *lasts = cast(char*)"";
        return null;
    }
    send = sbegin + kstrcspn(sbegin, s2);
    if (*send != '\0')
        *send++ = '\0';
    *lasts = send;
    return sbegin;
}

char* kstrtok(char* s1, char* s2) @nogc nothrow
{
    static char* ssave = cast(char*)"";
    return kstrtok_r(s1, s2, &ssave);
}

size_t kstrlen(char* s) @nogc nothrow
{
    char *p = s;
    while (*p != '\0')
        p++;
    return cast(size_t)(p - s);
}

wchar_t* kwmemchr(wchar_t* s, wchar_t uc, size_t n) @nogc nothrow
{
    wchar_t *src = s;
    while (n-- != 0) {
        if (*src == uc)
            return src;
        src++;
    }
    return null;
}

int kwmemcmp(wchar_t* dst, wchar_t* src, size_t size) @nogc nothrow
{
    size_t* plDst = cast(size_t*) dst;
    size_t* plSrc = cast(size_t*) src;
    if(!(cast(size_t)src & 0xFFFFFFFC) && !(cast(size_t)dst & 0xFFFFFFFC))
    {
        while(size >= 4)
        {
            if(*plDst++ == *plSrc++)
            {
                size -= 4;
            }
            else
            {
                return 0;
            }
        }
    }
    wchar_t* pcDst = cast(wchar_t*) plDst;
    wchar_t* pcSrc = cast(wchar_t*) plSrc;
    while(--size)
    {
        if(*pcDst++ != *pcSrc++)
        {
            return 0;
        }
    }
    return 1;
}

wchar_t* kwmemcpy(wchar_t* dst, wchar_t* src, size_t size) @nogc nothrow
{
    size_t* plDst = cast(size_t*) dst;
    size_t* plSrc = cast(size_t*) src;
    if(!(cast(size_t)src & 0xFFFFFFFC) && !(cast(size_t)dst & 0xFFFFFFFC))
    {
        while(size >= 4)
        {
            *plDst++ = *plSrc++;
            size -= 4;
        }
    }
    wchar_t* pcDst = cast(wchar_t*) plDst;
    wchar_t* pcSrc = cast(wchar_t*) plSrc;
    while(--size)
    {
        *pcDst++ = *pcSrc++;
    }
    return dst;
}

wchar_t* kwmemmove(wchar_t* dst, wchar_t* src, size_t size) @nogc nothrow
{
    size_t* plDst = cast(size_t*) dst;
    size_t* plSrc = cast(size_t*) src;
    
    if (plSrc < plDst && plDst < plSrc + size) 
    {
        plSrc += size;
        plDst += size;
        if(!(cast(size_t)src & 0xFFFFFFFC) && !(cast(size_t)dst & 0xFFFFFFFC))
        {
            while(size >= 4)
            {
                *--plDst = *--plSrc;
                size -= 4;
            }
        }
        wchar_t* pcDst = cast(wchar_t*) plDst;
        wchar_t* pcSrc = cast(wchar_t*) plSrc;
        while(--size)
        {
            *--pcDst = *--pcSrc;
        }
        return dst;
    }
    else
    {
        if(!(cast(size_t)src & 0xFFFFFFFC) && !(cast(size_t)dst & 0xFFFFFFFC))
        {
            while(size >= 4)
            {
                *plDst++ = *plSrc++;
                size -= 4;
            }
        }
        wchar_t* pcDst = cast(wchar_t*) plDst;
        wchar_t* pcSrc = cast(wchar_t*) plSrc;
        while(--size)
        {
            *pcDst++ = *pcSrc++;
        }
        return dst;
    }
}

wchar_t* kwmemset(wchar_t* dst, wchar_t c, size_t size) @nogc nothrow
{
    while(--size)
    {
        *dst++ = c;
    }
    return dst;
}

wchar_t* kwcscpy(wchar_t* s1, wchar_t* s2) @nogc nothrow
{
    wchar_t *dst = s1;
    wchar_t *src = s2;
    while ((*dst++ = *src++) != '\0') {}
    return s1;
}

wchar_t* kwcsncpy(wchar_t* s1, wchar_t* s2, size_t n) @nogc nothrow
{
    wchar_t *dst = s1;
    wchar_t *src = s2;
    while (n > 0) 
    {
        n--;
        if ((*dst++ = *src++) == '\0') 
        {
            kmemset(dst, '\0', n);
            break;
        }
    }
    return s1;
}

wchar_t* kwcscat(wchar_t* s1, wchar_t* s2) @nogc nothrow
{
    wchar_t *s = s1;
    while (*s != '\0')
        s++;
    kwcscpy(s, s2);
    return s1;
}

wchar_t* kwcsncat(wchar_t* s1, wchar_t* s2, size_t n) @nogc nothrow
{
    wchar_t *s = s1;
    while (*s != '\0') s++;
    while (n != 0 && (*s = *s2++) != '\0') 
    {
        n--;
        s++;
    }
    if (*s != '\0')
        *s = '\0';
    return s1;
}

int kwcscmp(wchar_t* s1, wchar_t* s2) @nogc nothrow
{
    wchar_t uc1, uc2;
    while (*s1 != '\0' && *s1 == *s2) 
    {
        s1++;
        s2++;
    }
    uc1 = (*s1);
    uc2 = (*s2);
    return ((uc1 < uc2) ? -1 : (uc1 > uc2));
}

int kwcsncmp(wchar_t* s1, wchar_t* s2, size_t n) @nogc nothrow
{
    wchar_t uc1, uc2;
    if (n == 0)
        return 0;
    while (n-- > 0 && *s1 == *s2) {
        if (n == 0 || *s1 == '\0')
            return 0;
        s1++;
        s2++;
    }
    uc1 = (*s1);
    uc2 = (*s2);
    return ((uc1 < uc2) ? -1 : (uc1 > uc2));
}

wchar_t* kwcschr(wchar_t* s, int c) @nogc nothrow
{
    while (*s != '\0' && *s != c)
        s++;
    return ( (*s == c) ? cast(wchar_t *) s : null );
}

size_t kwcscspn(wchar_t* s1, wchar_t* s2) @nogc nothrow
{
    wchar_t *sc1;
    for (sc1 = s1; *sc1 != '\0'; sc1++)
        if (kwcschr(s2, *sc1) != null)
            return (sc1 - s1);
    return sc1 - s1;
}

wchar_t* kwcspbrk(wchar_t* s1, wchar_t* s2) @nogc nothrow
{
    wchar_t *sc1;
    for (sc1 = s1; *sc1 != '\0'; sc1++)
        if (kwcschr(s2, *sc1) != null)
            return cast(wchar_t *)sc1;
    return null;
}

wchar_t* kwcsrchr(wchar_t* s, int c) @nogc nothrow
{
    wchar_t *last = null;
    if (c == '\0')
        return kwcschr(s, c);
    while ((s = kwcschr(s, c)) != null) 
    {
        last = s;
        s++;
    }
    return cast(wchar_t *) last;
}

size_t kwcsspn(wchar_t* s1, wchar_t* s2) @nogc nothrow
{
    wchar_t *sc1;
    for (sc1 = s1; *sc1 != '\0'; sc1++)
        if (kwcschr(s2, *sc1) == null)
            return (sc1 - s1);
    return sc1 - s1;
}

wchar_t* kwcsstr(wchar_t* s1, wchar_t* s2) @nogc nothrow
{
    size_t s2len;
    if (*s2 == '\0')
        return cast(wchar_t *) s1;
    s2len = kwcslen(s2);
    for (; (s1 = kwcschr(s1, *s2)) != null; s1++)
        if (kwcsncmp(s1, s2, s2len) == 0)
            return cast(wchar_t *) s1;
    return null;
}

wchar_t* kwcstok_r(wchar_t* s1, wchar_t* s2, wchar_t** lasts) @nogc nothrow
{
    wchar_t *sbegin;
    wchar_t *send;
    sbegin = s1 ? s1 : *lasts;
    sbegin += kwcsspn(sbegin, s2);
    if (*sbegin == '\0') {
        *lasts = cast(wchar_t*)"";
        return null;
    }
    send = sbegin + kwcscspn(sbegin, s2);
    if (*send != '\0')
        *send++ = '\0';
    *lasts = send;
    return sbegin;
}

wchar_t* kwcstok(wchar_t* s1, wchar_t* s2) @nogc nothrow
{
    static wchar_t* ssave = cast(wchar_t*)"";
    return kwcstok_r(s1, s2, &ssave);
}

size_t kwcslen(wchar_t* s) @nogc nothrow
{
    wchar_t *p = s;
    while (*p != '\0')
        p++;
    return cast(size_t)(p - s);
}
