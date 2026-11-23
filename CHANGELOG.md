DIOS 0.5.0 - TBD
----------------
- **ulib**:
  - New functions `memcmp`, `uputi`.

DIOS 0.4.0 - 23 Nov, 2026
-------------------------
- **Kernel**:
  - Multi-tasking support
  - New shell commands `ps`, `kill`, `fg`
  - Ability to run programs in background with `&` postfix
- **ulib**:
  - Runtime entry point that allocates an arguments array and calls compiler-generated `_Dmain`
  - `ulib.math` - elementary math functions
  - `ulib.core.traits`.

DIOS 0.3.1 - 22 Nov, 2026
-------------------------
- USB hot-plug support
- USB hubs support.

DIOS 0.3.0 - 22 Nov, 2026
-------------------------
- Kernel heap allocator
- Userspace heap alloactor
- A single-mount read-only filesystem
- USB mass storage devices; FAT32 and exFAT support
- Running programs from a USB stick
- FS syscalls
- New date-time module; `time` shell command
- Kernel log; `dmesg` shell command
- New workflow for building sample applications.

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

Early development (c. 2017 - 2020)
----------------------------------
- GRUB/Multiboot
- VGA text mode
- Basic console output.
