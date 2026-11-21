# DIOS

<img align="left" alt="dios logo" src="https://github.com/gecko0307/dios/raw/main/media/logo_128.png" height="80" />

DIOS stands for D Incomplete Operating System (because it is a toy project that will likely never be feature-complete). It is a minimal x86_64 OS kernel written in D with some parts in assembly. It is tested on a real hardware and emulators like VirtualBox and QEMU. The main purpose of this project is demonstrating D's fitness for system development. I've written it initially in D1/GDC and ported to D2/LDC in 2025.

You are free to use this code as a base to create your own kernel. PRs implementing real-world OS features are welcome. The code is a bit messy but readable.

DIOS is an ELF kernel that requires a bootloader to run. Default setup in this repo uses [Limine](https://github.com/limine-bootloader/limine) for booting from the CD-ROM. Both UEFI and BIOS are supported. You can also make a bootable USB stick with the DIOS ISO image using [Ventoy](https://www.ventoy.net/en/index.html).

[![Screenshot](media/screenshot.png)](media/screenshot.png)

## Features

- Boots using Limine startup protocol
- UEFI/GOP framebuffer
- IDT, GDT
- Bitmap page-frame allocator
- HPET timer (plus legacy PIT fallback)
- Minimal ACPI table reader
- I/O APIC, Local APIC
- PCI enumeration
- xHCI driver
- USB and PS/2 keyboard and mouse
- A shell with built-in kernel commands
- Basic single-tasking userspace in Ring 3; system calls.

DIOS is planned as a graphical OS: all rendering features are built into the kernel (but there's no full-featured GUI yet).

DIOS is now 64-bit only, x86 support was dropped.

## Kernel Shell Commands

After successful initialization, the kernel immediately starts an interactive shell session.

- `help` - show the command list
- `about` - kernel version information
- `cpuinfo` - CPU identification and features
- `mem` - physical memory statistics
- `uptime` - time since boot
- `clock` - clock source and timer status
- `irq` - interrupt controller status
- `irqstat` - interrupt counts per vector
- `pci` - enumerate PCI functions
- `hexdump [-p] ADDR [LEN]` - dump memory (-p: physical address)
- `history` - show recent commands
- `echo TEXT` - print TEXT
- `sleep SECONDS` - wait (Ctrl+C aborts)
- `ls` - list programs on the boot media
- `run NAME [ARGS]` - run a program (or just type its name)
- `clear` - clear the screen
- `crash pf|ud|div|gp` - trigger a CPU exception (kernel halts)
- `reboot` - restart the computer
- `poweroff` - shut down the computer.

## Programs

These are currently simple examples of what can be done in DIOS userspace.

- `hello` - "Hello, World!" program that prints its arguments
- `count` - counts once a second. Ctrl+C stops it (the kernel handles that)
- `rev` - reads lines and prints them reversed. An empty line ends the program
- `fault` - deliberately crashes by dereferencing a null pointer. The kernel reports it and keeps running.

Programs are also written in D and compiled with the kernel to *.elf files. At runtime they are currently loaded by Limine as kernel modules (the kernel itself doesn't have a file system).

## Code Structure

- `src/kernel` contains the kernel code:
  - `src/kernel/dios/bootloader` - boot protocol; currently only Limine protocol is implemented. Multiboot support was dropped
  - `src/kernel/dios/core` - kernel modules, including core drivers necessary to run the main I/O loop
  - `src/kernel/main.d` - the kernel entry point
- `src/user` contains sample userspace programs that are provided by the bootloader:
  - `src/user/count.d`
  - `src/user/fault.d`
  - `src/user/hello.d`
  - `src/user/rev.d`

## Building

Prerequisites:

* Recent [LDC](https://github.com/ldc-developers/ldc)
* [NASM](http://www.nasm.us)
* Python (for running the build script)
* [xorriso](https://github.com/Distrotech/xorriso) to generate a bootable CD image

Run `python build.py` to compile the kernel (`cdroot/kernel64.bin`) and generate `dios64.iso`.
