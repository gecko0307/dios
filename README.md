# DIOS

DIOS stands for *Desktop-oriented Independent Operating System*. It is a minimalistic multi-tasking x86_64 OS written in [D language](https://dlang.org) with some small parts in NASM assembly. It is tested on a real hardware and emulators like VirtualBox and QEMU.

DIOS does not replicate either Unix or Windows. While some parts of the system are modeled after Unix and others are inspired by Windows, this is only to keep a degree of familiarity with existing systems for better user experience. The goal is not to create a complete clone of any existing architecture. The purpose of DIOS is experimenting with system APIs and desktop environment design.

You can use DIOS as a basis for creating your own operating system! PRs implementing new features are welcome. The code is a bit messy but readable.

[![Screenshot8](media/screenshot8.jpg?raw=true)](media/screenshot8.jpg?raw=true)
[![Screenshot7](media/screenshot7.jpg?raw=true)](media/screenshot7.jpg?raw=true)

## Notes

- DIOS is a monolithic kernel that contains all the device drivers in itself. It is mostly designed for modern computers and doesn't support legacy hardware
- DIOS is now 64-bit only, x86 support was dropped
- DIOS is planned as a graphical OS, but there's no built-in GUI toolkit yet. Graphical features are work-in-progress
- DIOS is an ELF kernel that requires a bootloader to run. Currently only [Limine](https://github.com/limine-bootloader/limine) boot protocol is supported
- Default setup in this repo assumes booting from the CD-ROM, but you can also make a bootable USB stick with the DIOS ISO image using [Ventoy](https://www.ventoy.net/en/index.html). Simply copy the `dios-X.X.X-x86_64.iso` file onto the flash drive that has Ventoy installed.

## Features

- Thanks to Limine, DIOS is compatible with both UEFI and BIOS
- UEFI GOP (or VESA) framebuffer
- IDT, GDT
- Bitmap page-frame allocator
- Low-latency HPET-based timer (plus legacy PIT fallback). System tick frequency is 1000 Hz
- Minimal ACPI table reader
- I/O APIC, Local APIC
- CMOS date-time
- PCI enumeration
- Block device interface
- FAT32 (read-write) and exFAT (read-only)
- SATA driver
- xHCI driver. USB keyboard and mouse; mass storage devices; USB hot-plug support; USB hubs support
- PS/2 keyboard and mouse
- A shell with built-in kernel commands
- Basic multi-tasking userspace in Ring 3; system calls; a simple standard library for applications
- Spawning processes from other processes
- Virtual filesystem; multiple mount points
- RAM filesystem image loaded from a TAR archive (`rootfs.tar`) provided by the bootloader
- Standard output channels
- Userspace graphics server (GFXD), windowed applications
- Work-in-progress desktop manager
- A number of basic built-in applications.

Note: all storage devices are mounted as read-only by default. FAT32 partitions can be remounted as read/write; exFAT is currently read-only.

## Command Shell

After successful initialization, the kernel immediately starts a graphics mode and runs its own shell at the background. You can always switch to the shell with `Ctrl+F1` and back to graphics with `Ctrl+F2`. Available shell commands are listed [here](doc/commands.md).

In the graphics mode, you can open a terminal window by pressing a launcher button. Terminal's possibilities are quite limited at the moment, but you already can run built-in programs. For example:

- `about` - prints the information about the system
- `time` - prints current date and time
- `file /home/hello.txt` - prints a text file
- `image /home/lake.tga &` - displays a TGA image
- `blackboard &` - a simple sketching app.

Full list of built-in programs is [here](doc/programs.md).

The repo also contains a number of simple examples of what can be done in DIOS userspace. They are included in the prebuilt ISO image:

- `hello` - "Hello, World!" program that prints its arguments
- `memtest` - dynamic memory allocation test
- `math` - floating-point math functions test
- `random` - random number generator test.

Applications are also written in D, but they actually can be written in any language that can make platform-independent ELF64 binaries.

## Code Structure

DIOS project consists of a several structural layers, each with its own workflow.

- `src/kernel` contains the kernel code
- `src/ulib` contains the **ulib** runtime library code
- `src/user` contains built-in programs
- `src/demos` contains sample applications.

## ulib

ulib stands for "user library". It is a low-level runtime for DIOS applications written in D.

Most of its functions are libc-like and self-explanatory. Full list of them can be found [here](doc/ulib.md).

## GFXD

[GFXD](src/user/gfxd) is a graphics server and a window manager that allows other applications to create windows and draw graphics. It is a userspace program that must be present as `/bin/gfxd.elf` in the root filesystem.

When the kernel is started with `gfx` argument (first boot option in the list), GFXD is launched automatically. If you accidently booted the system in shell mode, you can start GFXD by running `gfx start` command. `Ctrl+F1` switches back to the shell, `Ctrl+F2` shows the server, `Ctrl+F3` stops it.

## "Hello, World" application in D

```d
import ulib.dios;

void main(string[] args)
{
    uprintf("Hello, World!\n");
}
```

ulib is currently statically linked; DIOS doesn't support dynamic linking yet.

## Building

DIOS uses its own build system written in Python that compiles the entire system. It does the following:

- Compiles the kernel (by default `cdroot/kernel64.bin`)
- Compiles ulib (`rootfs/lib/libulib.a`)
- Compiles userspace programs (`rootfs/bin/*.elf`)
- Builds the root filesystem image (`cdroot/rootfs.tar`)
- Generates a bootable CD image (`dios64.iso`).

Prerequisites:

- Recent [LDC](https://github.com/ldc-developers/ldc)
- [NASM](http://www.nasm.us)
- Python (for running the build script)
- [xorriso](https://github.com/Distrotech/xorriso) to generate a bootable CD image
- Optionally, [fstool](https://github.com/KarpelesLab/fstool) to generate a USB stick image for testing in QEMU.

Run `python build.py` to build everything.

Run `python build.py kernel` to build only the kernel.

Run `python build.py ulib` to build only ulib.

Run `python build.py user` to build only the userspace.

Userspace and sample programs (`src/demos`) can be built individually with DUB:

```
dub build
```

All *.elf binaries of the demos are automatically copied to `rootfs/bin`. To include them to the root filesystem, you should run `python build.py rootfs` to rebuild the image.

## Running in QEMU

Tianocore's [Open Virtual Machine Firmware](https://wiki.osdev.org/OVMF) is required.

```
qemu-system-x86_64 -cpu max,+rdrand -cdrom dios-0.9.0-x86_64.iso -m 512M -bios OVMF.fd -vga std -device qemu-xhci,id=xhci -device usb-mouse,bus=xhci.0,port=1 -d guest_errors
```
