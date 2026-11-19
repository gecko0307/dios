# DIOS

<img align="left" alt="dios logo" src="https://github.com/gecko0307/mathom/raw/master/dios/logo_128.png" height="80" />

DIOS stands for D Incomplete Operating System. It is a minimal x86_64 OS kernel written in D with some parts in assembly. It is tested on a real hardware and emulators like VirtualBox and QEMU. The main purpose of this project is demonstrating D's fitness for system development. I've written it initially in D1/GDC and recently ported to D2/LDC.

You are free to use this code as a base to create your own kernel. PRs implementing real-world OS features are welcome. The code is a bit messy but readable.

DIOS is an ELF kernel that requires a bootloader to run. Default setup in this repo uses Limine for booting from the CD-ROM. You can also make a bootable USB stick with the DIOS ISO image using [Ventoy](https://www.ventoy.net/en/index.html).

## Features

- Boots using Limine startup protocol
- UEFI/GOP framebuffer
- Double buffering
- Bitmap page-frame allocator
- PIT timer
- PS/2 keyboard and mouse
- xHCI driver, HID mouse
- Simple console.

DIOS is planned as a graphical OS, all rendering features are built into the kernel (but there's no full-featured GUI yet).

## Building

Prerequisites:

* Recent LDC compiler
* [NASM](http://www.nasm.us)
* [xorriso](https://github.com/Distrotech/xorriso) to generate bootable CD image

Run `./build64.bat` to compile the kernel (`cdroot64/kernel64.bin`) and generate `dios64.iso`.
