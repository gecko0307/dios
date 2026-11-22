# DIOS

<img align="left" alt="dios logo" src="https://github.com/gecko0307/dios/raw/main/media/logo_128.png" height="80" />

DIOS stands for D Incomplete Operating System (because it is a toy project that will likely never be feature-complete). It is a minimalistic single-tasking x86_64 OS kernel written in [D language](https://dlang.org) with some parts in NASM assembly. It is tested on a real hardware and emulators like VirtualBox and QEMU. The main purpose of this project is demonstrating D's fitness for system development. I've written it initially in D1/GDC and ported to D2/LDC in 2025.

You are free to use this code as a base to create your own kernel. PRs implementing new features are welcome. The code is a bit messy but readable.

DIOS is an ELF kernel that requires a bootloader to run. Default setup in this repo uses [Limine](https://github.com/limine-bootloader/limine) for booting from the CD-ROM. Both UEFI and BIOS are supported. You can also make a bootable USB stick with the DIOS ISO image using [Ventoy](https://www.ventoy.net/en/index.html).

[![Screenshot](media/screenshot.png)](media/screenshot.png)

## Features

- Boots using Limine startup protocol; supports both UEFI and legacy BIOS
- UEFI/GOP framebuffer
- IDT, GDT
- Bitmap page-frame allocator
- HPET timer (plus legacy PIT fallback)
- Minimal ACPI table reader
- I/O APIC, Local APIC
- PCI enumeration
- xHCI driver
- USB and PS/2 keyboard and mouse
- CMOS date-time reading
- A shell with built-in kernel commands
- A single-mount read-only filesystem
- USB mass storage devices (FAT32, exFAT)
- Basic single-tasking userspace in Ring 3; system calls
- A simple standard library for applications
- Running applications from a USB stick.

DIOS is planned as a graphical OS: all rendering features are built into the kernel (but there's no full-featured GUI yet).

DIOS is now 64-bit only, x86 support was dropped.

## Kernel Shell Commands

After successful initialization, the kernel immediately starts an interactive shell session.

- `help` - show the command list
- `about` - kernel version information
- `cpuinfo` - CPU identification and features
- `mem` - physical memory statistics
- `memmap` - show the memory map
- `time` - print current date and time
- `uptime` - time since boot
- `clock` - clock source and timer status
- `irq` - interrupt controller status
- `irqstat` - interrupt counts per vector
- `pci` - enumerate PCI functions
- `hexdump [-p] ADDR [LEN]` - dump memory (-p: physical address)
- `history` - show recent commands
- `echo TEXT` - print TEXT
- `sleep SECONDS` - wait (Ctrl+C aborts)
- `dmesg [N [SKIP]]` - kernel log (last N lines, SKIP lines before the end)
- `programs` - list programs on the boot media
- `disk` - show USB disks and partitions
- `mount [N]` - mount an exFAT partition as `/`
- `ls [PATH]` - list a directory on the mounted volume
- `cd [DIR]` - change the current directory
- `pwd` - show the current directory
- `cat FILE` - print a text file
- `run NAME [ARGS]` - run a boot program or an ELF from the disk
- `clear` - clear the screen
- `crash pf|ud|div|gp` - trigger a CPU exception (kernel halts)
- `reboot` - restart the computer
- `poweroff` - shut down the computer.

## Programs

Simple examples of what can be done in DIOS userspace.

- `hello.elf` - "Hello, World!" program that prints its arguments
- `file.elf FILE [OFFSET]`  - print a text file, optionally starting at a byte offset.
- `dir.elf [PATH]` - lists a directory
- `memtest.elf` - dynamic memory allocation test.

Programs are also written in D (in fact, they can be written in any language that outputs ELF64).

## Code Structure

- `src/kernel` contains the kernel code:
  - `src/kernel/dios/bootloader` - boot protocol; currently only Limine protocol is implemented. Multiboot support was dropped
  - `src/kernel/dios/core` - kernel modules, including core drivers necessary to run the main I/O loop
  - `src/kernel/main.d` - the kernel entry point
- `src/ulib` contains the ulib runtime library code:
  - `src/ulib/dios` - implements basic functionality on top of DIOS syscalls
- `userspace` contains sample userspace programs:
  - `userspace/hello`
  - `userspace/file`
  - `userspace/dir`
  - `userspace/memtest`

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

Binaries are automatically copied to `usbstick` directory. When running on a real hardware, they are meant to be copied to USB stick alongside with the DIOS kernel. When testing in QEMU, it is recommended to make a USB stick image using fstool (`makestick.bat`) and run the VM via `run_usbstick.bat`.
