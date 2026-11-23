# DIOS

<img align="left" alt="dios logo" src="https://github.com/gecko0307/dios/raw/main/media/logo_128.png" height="80" />

DIOS stands for *D Incomplete Operating System* (because it is a toy project that will likely never be feature-complete). It is a minimalistic multi-tasking x86_64 OS kernel written in [D language](https://dlang.org) with some parts in NASM assembly. It is tested on a real hardware and emulators like VirtualBox and QEMU. The main purpose of this project is demonstrating D's fitness for system development. I've written it initially in D1/GDC and ported to D2/LDC in 2025.

You are free to use this code as a base to create your own kernel. PRs implementing new features are welcome. The code is a bit messy but readable.

DIOS is an ELF kernel that requires a bootloader to run. Default setup in this repo uses [Limine](https://github.com/limine-bootloader/limine) for booting from the CD-ROM. Both UEFI and BIOS are supported. You can also make a bootable USB stick with the DIOS ISO image using [Ventoy](https://www.ventoy.net/en/index.html).

[![Screenshot](media/screenshot.png)](media/screenshot.png)

## Features

DIOS is a monolithic kernel that contains all the device drivers in itself. It is mostly designed for modern computers and doesn't support legacy hardware.

- Boots using Limine startup protocol; supports both UEFI and legacy BIOS
- UEFI GOP (or VESA) framebuffer
- IDT, GDT
- Bitmap page-frame allocator
- Low-latency HPET-based timer (plus legacy PIT fallback). System tick frequency is 1000 Hz
- Minimal ACPI table reader
- I/O APIC, Local APIC
- CMOS date-time
- PCI enumeration
- xHCI driver. USB keyboard and mouse; mass storage devices (FAT32, exFAT); USB hot-plug support; USB hubs support
- PS/2 keyboard and mouse
- A shell with built-in kernel commands
- Basic multi-tasking userspace in Ring 3; system calls; a simple standard library for applications
- A single-mount read-only filesystem
- Running applications from a USB stick.

DIOS is planned as a graphical OS: all rendering features are built into the kernel (but there's no full-featured GUI yet).

DIOS is now 64-bit only, x86 support was dropped.

## Kernel Shell Commands

After successful initialization, the kernel immediately starts an interactive shell session. Available commands are listed [here](doc/commands.md).

## Applications

Simple examples of what can be done in DIOS userspace.

- `hello.elf` - "Hello, World!" program that prints its arguments
- `file.elf FILE [OFFSET]` - print a text file, optionally starting at a byte offset.
- `dir.elf [PATH]` - lists a directory
- `memtest.elf` - dynamic memory allocation test
- `timer.elf` - a timer that can be run in background (for example, `timer.elf 10s &`)
- `math.elf` - floating-point math functions test.

Applications are also written in D, but they actually can be written in any language that can make platform-independent ELF64 binaries.

## Code Structure

DIOS project consists of a several structural layers, each with its own workflow.

- `src/kernel` contains the kernel code:
  - `src/kernel/dios/bootloader` - boot protocol; currently only Limine protocol is implemented. Multiboot support was dropped
  - `src/kernel/dios/core` - kernel modules, including core drivers necessary to run the main I/O loop
  - `src/kernel/main.d` - the kernel entry point
- `src/ulib` contains the **ulib** runtime library code:
  - `src/ulib/ulib/dios` - implements basic libc-like functionality on top of [DIOS syscalls](doc/sys_call.md)
  - `src/ulib/umain.d` - runtime entry point. Allocates an arguments array and calls compiler-generated `_Dmain`
- `src/user` contains sample userspace programs:
  - `src/user/hello`
  - `src/user/file`
  - `src/user/dir`
  - `src/user/memtest`
  - `src/user/timer`
  - `src/user/math`

## ulib

ulib stands for "user library" (or, alternatively, "unfinished library" because, again, it is a hobby project that will likely never be finished). It is a low-level runtime library for DIOS applications written in D.

Most of its functions are libc-like and self-explanatory. Full list of them can be found [here](doc/ulib.md).

## "Hello, World" application in D

```d
import ulib.dios;

void main(string[] args)
{
    uputs("Hello, World!\n");
}
```

ulib is currently statically linked; DIOS doesn't support dynamic linking yet.

## Building

Prerequisites:

* Recent [LDC](https://github.com/ldc-developers/ldc)
* [NASM](http://www.nasm.us)
* Python (for running the build script)
* [xorriso](https://github.com/Distrotech/xorriso) to generate a bootable CD image
* Optionally, [fstool](https://github.com/KarpelesLab/fstool) to generate a USB stick image for testing in QEMU

Run `python build.py` to compile the kernel (`cdroot/kernel64.bin`) and generate `dios64.iso`.

Run `buildlib.bat` to compile ulib and generate `libulib.a`. This is necessary to build sample programs.

All sample programs are built with DUB:

```
dub build
```

*.elf binaries are automatically copied to `usbstick` directory. When running on a real hardware, they are meant to be copied to USB stick alongside with the DIOS kernel. When testing in QEMU, it is recommended to make a USB stick image using fstool (`makestick.bat`) and run the VM via `run_usbstick.bat`.
