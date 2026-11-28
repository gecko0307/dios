# DIOS Live Installation

DIOS can be installed on a SATA disk in live mode (under a system booted from Live CD/USB). This is currently a complex manual task that is not meant for beginners. Don't try it unless you fully understand what you are doing!

If you prefer to install the system in a familiar environment such as Linux, follow the [offline installation guide](offline_installation.md).

**Warning! Install DIOS at your own risk! The system is experimental and unstable.**

## Part 1. Preparing the Disk

If the disk is already in use, unmount it:

```
umount sata0p1
```

Create a new empty partition table (this will **erase the disk's existing partitions**):

```
ptable sata0 gpt yes
```

Add two partitions: a BIOS boot partition without a filesystem, and a primary FAT32 partition (that will be seen to the system as `sata0p2`):

```
padd sata0 bios
padd sata0 rest esp
mkfs 1 DIOS yes
```

Install the BIOS bootloader to the boot partition:

```
biosinstall sata0 yes
```

## Part 2. Copying the System

Mount the primary partition in read/write mode:

```
mount 1 sata0p2 rw
```

Install the system to the primary partition:

```
ramcopy sata0p2
```

You can make it the root and check that the files were copied, just in case:

```
rmount sata0p2 rw
ls /
```

The console should print something like

```
2026-11-28     <DIR>  bin
2026-11-28     <DIR>  etc
2026-11-28     <DIR>  home
2026-11-28     <DIR>  kernel
2026-11-28     <DIR>  lib
2026-11-28     <DIR>  boot
2026-11-28     <DIR>  EFI
1980-00-00     <DIR>  mnt
0 file(s), 8 dir(s)
```

Remove the boot media (CD/USB) and reboot:

```
reboot
```
