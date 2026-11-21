module rev;

import ulib;

// Reads lines and prints them reversed. An empty line ends the program.
extern(C) int umain(const(char)* args) @nogc nothrow
{
    char[128] line;
    uputs("Type a line, Enter reverses it, empty line quits.\n");
    for (;;)
    {
        uputs("rev> ");
        size_t len = 0;
        for (;;)
        {
            int k = ugetkey(true);
            if (k == 10)
            {
                uputc('\n');
                break;
            }
            if (k == 8)
            {
                if (len > 0)
                {
                    len--;
                    uputc(cast(char)8);
                }
            }
            else if (k >= 32 && k < 127 && len < line.length)
            {
                line[len++] = cast(char)k;
                uputc(cast(char)k);
            }
        }
        if (len == 0)
            return 0;
        for (size_t i = len; i > 0; i--)
            uputc(line[i - 1]);
        uputc('\n');
    }
}
