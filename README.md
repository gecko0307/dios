<img align="left" alt="dios logo" src="https://github.com/gecko0307/mathom/raw/master/dios/logo_128.png" height="128" />

DIOS is a minimal i386 operating system kernel written in D with some parts in assembly. It is tested on a real hardware and emulators like VirtualBox and QEMU. The main purpose of this project is demonstrating D's fitness for system development. I've written it initially in D1/GDC and recently ported to D2/LDC.

I don't have any big plans for this code - you are free to use it to create your own kernel. PRs implementing real-world OS features are welcome.

DIOS is an ELF kernel that requires a bootloader to run. Default setup in this repo uses GRUB2 eltorito.img for booting from the CD-ROM. You can also make a bootable USB stick with the DIOS ISO image using [Ventoy](https://www.ventoy.net/en/index.html).

Features
--------
DIOS 0.0.2 boots up in 640x480 VESA graphics mode, gets Multiboot info from GRUB, draws bitmaps on the screen, supports keyboard and mouse.

Building
--------
Prerequisites:
* Recent LDC compiler
* [NASM](http://www.nasm.us)
* mkisofs to generate Live CD

1. Run `./build.bat`
2. You're done! Newly generated CD image is `dios.iso`. If you have QEMU installed, you can run it with `run.bat`.
