# DIOS Virtual Filesystem

DIOS implements a root filesystem conceptually analogous to Unix filesystem. The root is `/`. The following standard directories are used:

- `/bin` - contains programs. These are system services and utilities provided with the OS
- `/etc` - contains data and configuration files used by the programs
- `/home` - user's home folder, contains custom files
- `/mnt` - contains mount points for disks (e.g. `/mnt/usb0p1`).

The root filesystem is loaded from a TAR archive (`rootfs.tar`) provided by the bootloader. You can put any custom files to this archive to make them available to the kernel immediately after the boot, before any storage devices are mounted.
