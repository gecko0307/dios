<img align="left" alt="dios logo" src="https://github.com/gecko0307/mathom/raw/master/dios/logo_128.png" height="80" />

DIOS is a minimal x86/x86_64 OS kernel written in D with some parts in assembly. It is tested on a real hardware and emulators like VirtualBox and QEMU. The main purpose of this project is demonstrating D's fitness for system development. I've written it initially in D1/GDC and recently ported to D2/LDC and added 64-bit support.

I don't have any big plans for this code - you are free to use it to create your own kernel. PRs implementing real-world OS features are welcome. The code is a bit messy but readable.

DIOS is an ELF kernel that requires a bootloader to run. Default setup in this repo uses GRUB2 (for i386) and Limine (for x86_64) for booting from the CD-ROM. You can also make a bootable USB stick with the DIOS ISO image using [Ventoy](https://www.ventoy.net/en/index.html).

Features
--------
- Boots using Multiboot or Limine startup protocols
- GOP framebuffer via Limine / VESA 640x480 via Multiboot
- Double buffering
- PIT timer
- PS/2 keyboard and mouse.

Building (i386)
--------------
Prerequisites:
* Recent LDC compiler
* [NASM](http://www.nasm.us)
* mkisofs to generate bootable CD image

Run `./build.bat` to compile the kernel (`cdroot/kernel.bin`) and generate `dios.iso`.

Building (x86_64)
--------------
Prerequisites:
* Recent LDC compiler
* [NASM](http://www.nasm.us)
* xorriso to generate bootable CD image

Run `./build64.bat` to compile the kernel (`cdroot64/kernel64.bin`) and generate `dios64.iso`.
