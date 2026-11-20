module dios.core.shell;

import dios.core.clock;
import dios.core.acpi;
import dios.core.console;
import dios.core.cpu;
import dios.core.interrupts;
import dios.core.keyboard;
import dios.core.paging;
import dios.core.pci;
import dios.core.stdio;

/// Fixed-size input and history storage: the kernel shell must not allocate.
enum size_t SHELL_LINE_CAPACITY = 128;
enum size_t SHELL_HISTORY_CAPACITY = 16;

immutable string[10] SHELL_COMMANDS = [
    "help", "about", "mem", "uptime", "clock",
    "irq", "pci", "history", "echo", "poweroff"
];

__gshared char[SHELL_LINE_CAPACITY] shellLine;
__gshared char[SHELL_LINE_CAPACITY][SHELL_HISTORY_CAPACITY] shellHistory;
__gshared size_t shellLineLength;
__gshared size_t shellHistoryCount;
__gshared size_t shellHistoryNext;

extern(C):

bool shellEquals(const(char)* value, string expected) @nogc nothrow
{
    size_t i = 0;
    while (i < expected.length)
    {
        if (value[i] == 0 || value[i] != expected[i])
            return false;
        i++;
    }
    return value[i] == 0;
}

bool shellStartsWith(const(char)* value, const(char)[] prefix) @nogc nothrow
{
    for (size_t i = 0; i < prefix.length; i++)
        if (value[i] == 0 || value[i] != prefix[i])
            return false;
    return true;
}

void shellCopy(char* dst, const(char)* src) @nogc nothrow
{
    size_t i = 0;
    while (i + 1 < SHELL_LINE_CAPACITY && src[i] != 0)
    {
        dst[i] = src[i];
        i++;
    }
    dst[i] = 0;
}

void shellPrompt() @nogc nothrow
{
    kprintf("dios> ");
}

void shellRememberCommand() @nogc nothrow
{
    if (shellLineLength == 0)
        return;

    // Do not add an identical command twice in a row.
    if (shellHistoryCount != 0)
    {
        size_t last = (shellHistoryNext + SHELL_HISTORY_CAPACITY - 1) % SHELL_HISTORY_CAPACITY;
        bool same = true;
        for (size_t i = 0; i < SHELL_LINE_CAPACITY; i++)
        {
            if (shellHistory[last][i] != shellLine[i])
            {
                same = false;
                break;
            }
            if (shellLine[i] == 0)
                break;
        }
        if (same)
            return;
    }

    shellCopy(shellHistory[shellHistoryNext].ptr, shellLine.ptr);
    shellHistoryNext = (shellHistoryNext + 1) % SHELL_HISTORY_CAPACITY;
    if (shellHistoryCount < SHELL_HISTORY_CAPACITY)
        shellHistoryCount++;
}

void shellShowHistory() @nogc nothrow
{
    if (shellHistoryCount == 0)
    {
        kprintf("Command history is empty.\n");
        return;
    }

    size_t first = (shellHistoryNext + SHELL_HISTORY_CAPACITY - shellHistoryCount) % SHELL_HISTORY_CAPACITY;
    for (size_t i = 0; i < shellHistoryCount; i++)
    {
        size_t index = (first + i) % SHELL_HISTORY_CAPACITY;
        kprintf("%u  %s\n", cast(uint)(i + 1), shellHistory[index].ptr);
    }
}

void shellShowPci() @nogc nothrow
{
    uint found = 0;
    for (uint bus = 0; bus < 256; bus++)
    {
        for (uint device = 0; device < 32; device++)
        {
            if (pciReadVendorID(bus, device, 0) == 0xFFFF)
                continue;

            uint functions = (pciReadHeaderType(bus, device, 0) & 0x80) ? 8 : 1;
            for (uint func = 0; func < functions; func++)
            {
                ushort vendor = pciReadVendorID(bus, device, func);
                if (vendor == 0xFFFF)
                    continue;

                ushort dev = pciReadDeviceID(bus, device, func);
                ubyte cls = pciReadClass(bus, device, func);
                ubyte sub = pciReadSubclass(bus, device, func);
                kprintf("%u:%u.%u  %k:%k  class %X/%X\n",
                    bus, device, func, vendor, dev, cls, sub);
                found++;
            }
        }
    }
    kprintf("%u PCI function(s) found.\n", found);
}

void shellExecute() @nogc nothrow
{
    // Split command and arguments in-place. Quoting is intentionally not
    // supported yet; these first built-ins only need a simple argument tail.
    size_t commandLength = 0;
    while (commandLength < shellLineLength && shellLine[commandLength] != ' ' && shellLine[commandLength] != '\t')
        commandLength++;

    char separator = shellLine[commandLength];
    shellLine[commandLength] = 0;
    const(char)* args = shellLine.ptr + commandLength + (separator != 0 ? 1 : 0);
    while (*args == ' ' || *args == '\t')
        args++;

    if (shellEquals(shellLine.ptr, "help"))
    {
        kprintf("DIOS kernel shell\n");
        kprintf("  help       Show this command list\n");
        kprintf("  about      Kernel version information\n");
        kprintf("  mem        Physical memory statistics\n");
        kprintf("  uptime     Time since boot\n");
        kprintf("  clock      Clock source and timer status\n");
        kprintf("  irq        Interrupt controller status\n");
        kprintf("  pci        Enumerate PCI functions\n");
        kprintf("  history    Show recent commands\n");
        kprintf("  echo TEXT  Print TEXT\n");
        kprintf("  poweroff   Shut down the computer\n");
    }
    else if (shellEquals(shellLine.ptr, "about"))
    {
        kprintf("DIOS 0.1.0 for x86_64\n");
    }
    else if (shellEquals(shellLine.ptr, "mem"))
    {
        ulong freePages = pmmFreeCount();
        ulong totalPages = pmmTotalCount();
        ulong usedPages = totalPages - freePages;
        kprintf("Physical memory (4 KiB pages):\n");
        kprintf("  Total: %llu MiB (%llu pages)\n",
            totalPages * MEM_PAGE_SIZE / (1024 * 1024), totalPages);
        kprintf("  Used:  %llu MiB (%llu pages)\n",
            usedPages * MEM_PAGE_SIZE / (1024 * 1024), usedPages);
        kprintf("  Free:  %llu MiB (%llu pages)\n",
            freePages * MEM_PAGE_SIZE / (1024 * 1024), freePages);
    }
    else if (shellEquals(shellLine.ptr, "uptime"))
    {
        ulong ms = clockNowNs() / 1_000_000;
        ulong seconds = ms / 1000;
        ulong days = seconds / 86400;
        ulong hours = (seconds / 3600) % 24;
        ulong minutes = (seconds / 60) % 60;
        ulong secs = seconds % 60;
        kprintf("Uptime: %llu day(s), %llu hour(s), %llu minute(s), %llu second(s)\n",
            days, hours, minutes, secs);
    }
    else if (shellEquals(shellLine.ptr, "clock"))
    {
        kprintf("Clock source: %s\n", clockHasHpet() ? "HPET".ptr : "PIT".ptr);
        if (clockHasHpet())
            kprintf("  HPET frequency: %llu Hz\n", hpetFreq);
        kprintf("  LAPIC tick: %s\n", clockTickActive() ? "active".ptr : "inactive".ptr);
        if (clockTickActive())
            kprintf("  Tick count: %llu\n", clockTickMs());
    }
    else if (shellEquals(shellLine.ptr, "irq"))
    {
        interruptsPrintStatus();
    }
    else if (shellEquals(shellLine.ptr, "pci"))
    {
        shellShowPci();
    }
    else if (shellEquals(shellLine.ptr, "history"))
    {
        shellShowHistory();
    }
    else if (shellEquals(shellLine.ptr, "echo"))
    {
        kprintf("%s\n", cast(char*)args);
    }
    else if (shellEquals(shellLine.ptr, "poweroff"))
    {
        kprintf("Powering off...\n");
        if (!acpiPoweroff())
            kprintf("ACPI shutdown is unavailable (missing FADT/DSDT _S5_ or PM1a control block).\n");
    }
    else if (shellLine[0] != 0)
    {
        kprintf("Unknown command: %s\n", shellLine.ptr);
        kprintf("Type 'help' for available commands.\n");
    }

    shellLine[] = 0;
    shellLineLength = 0;
    shellPrompt();
}

void shellComplete() @nogc nothrow
{
    string match;
    uint matches = 0;
    size_t commonLength = 0;

    for (size_t i = 0; i < SHELL_COMMANDS.length; i++)
    {
        if (!shellStartsWith(SHELL_COMMANDS[i].ptr, shellLine[0 .. shellLineLength]))
            continue;

        if (matches == 0)
        {
            match = SHELL_COMMANDS[i];
            commonLength = match.length;
        }
        else
        {
            size_t j = shellLineLength;
            while (j < commonLength && j < SHELL_COMMANDS[i].length && match[j] == SHELL_COMMANDS[i][j])
                j++;
            commonLength = j;
        }
        matches++;
    }

    if (matches == 0)
        return;

    if (commonLength > shellLineLength)
    {
        for (size_t i = shellLineLength; i < commonLength && i + 1 < SHELL_LINE_CAPACITY; i++)
        {
            shellLine[i] = match[i];
            consolePrintChar(match[i]);
        }
        shellLineLength = commonLength;
        shellLine[shellLineLength] = 0;
    }

    if (matches > 1 && commonLength == shellLineLength)
    {
        consoleNewline();
        for (size_t i = 0; i < SHELL_COMMANDS.length; i++)
            if (shellStartsWith(SHELL_COMMANDS[i].ptr, shellLine[0 .. shellLineLength]))
                kprintf("%s  ", SHELL_COMMANDS[i].ptr);
        consoleNewline();
        shellPrompt();
        for (size_t j = 0; j < shellLineLength; j++)
            consolePrintChar(shellLine[j]);
    }
}

void shellInit() @nogc nothrow
{
    shellLine[] = 0;
    shellLineLength = 0;
    shellHistoryCount = 0;
    shellHistoryNext = 0;
    kprintf("\nDIOS kernel shell ready. Type 'help' for commands.\n");
    shellPrompt();
}

/// Feed a decoded PS/2 make code to the shell from the main loop.
void shellHandleKey(ubyte scancode, bool shift) @nogc nothrow
{
    if (scancode == 0x0E) // Backspace
    {
        if (shellLineLength != 0)
        {
            shellLineLength--;
            shellLine[shellLineLength] = 0;
            consoleBack();
        }
        return;
    }

    if (scancode == 0x1C) // Enter
    {
        consoleNewline();
        shellLine[shellLineLength] = 0;
        shellRememberCommand();
        shellExecute();
        return;
    }

    if (scancode == 0x0F) // Tab
    {
        shellComplete();
        return;
    }

    if (scancode == 0x01) // Escape: clear current input
    {
        while (shellLineLength != 0)
        {
            shellLineLength--;
            shellLine[shellLineLength] = 0;
            consoleBack();
        }
        return;
    }

    char c = scancodeToChar(scancode, shift);
    if (c >= 32 && c < 127 && shellLineLength + 1 < SHELL_LINE_CAPACITY)
    {
        shellLine[shellLineLength++] = c;
        shellLine[shellLineLength] = 0;
        consolePrintChar(c);
    }
}
