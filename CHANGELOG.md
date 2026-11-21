DIOS 0.2.0 - 21 Nov, 2026
-------------------------
- Basic ELF64 userspace programs support. They are currently loaded by Limine as kernel modules (the kernel itself doesn't have a file system)
- CMOS date-time reading
- More kernel shell commands
- Switch to Python for building.

DIOS 0.1.0 - 21 Nov, 2026
-------------------------
- IDT
- GDT
- HPET timer that replaces the legacy PIT
- I/O APIC, Local APIC
- USB keyboard support; interrupt-driven PS/2 keyboard; Shift support
- A simple shell for running built-in kernel commands.

DIOS 0.0.4 - 20 Nov, 2026
-------------------------
- The kernel was ported to x86_64, support for x86 was dropped
- The bootloader is now Limine, which provides UEFI support
- Initial USB 3.0 support
- Many fixes and improvements across the codebase.

Early development (c. 2016 - 2020)
----------------------------------
- GRUB/Multiboot
- VGA text mode
- Basic console output.
