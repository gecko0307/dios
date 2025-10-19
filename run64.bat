qemu-system-x86_64 -cdrom dios64.iso -m 512M -bios OVMF.fd -vga std -device nec-usb-xhci,id=xhci,id=xhci -device usb-mouse,bus=xhci.0 -serial stdio
