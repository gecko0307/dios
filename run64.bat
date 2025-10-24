qemu-system-x86_64 -cdrom dios64.iso -m 512M -bios OVMF.fd -vga std -device qemu-xhci,id=xhci -device usb-mouse,bus=xhci.0,port=1 -d guest_errors
