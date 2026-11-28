# DIOS Installation

DIOS can be installed to a SATA disk. The disk should have a primary partition formatted to FAT32, and a BIOS boot partition for the bootloader. The following step-by-step describes the process under Linux, assuming the disk is `/dev/sdb`.

**Warning! Install DIOS at your own risk! The system is experimental and unstable.**

## Part 1. Preparing the Disk

Completely wipe old partition tables and create a new GPT:

```
sudo sgdisk --zap-all /dev/sdb
```

Partition 1 (`sata0p1` is DIOS) - primary system partition + ESP in FAT32 (starting at sector 2048):

```
sudo sgdisk -n 1:2048:0 -t 1:ef00 -c 1:"DIOS" /dev/sdb
```

Partition 2 (`sata0p2` in DIOS) - BIOS Boot Partition in the 34–2047 free gap (1 MB):

```
sudo sgdisk -n 2:34:2047 -t 2:ef02 -c 2:"BOOT" /dev/sdb
```

Inform the kernel of partition table changes:

```
sudo partprobe /dev/sdb
```

Format the first partition to FAT32:

```
sudo mkfs.fat -F 32 -n "DIOS" /dev/sdb1
```

Install the Limine MBR/Stage1.5 bootloader:

```
sudo ./limine bios-install /dev/sdb
```

Mount the primary system partition:

```
sudo mkdir /media/tim/DIOS
sudo mount -o rw,uid=$(id -u),gid=$(id -g),umask=0022 /dev/sdb1 /media/tim/DIOS
```

## Part 2. Preparing the OS

Copy DIOS files - contents of both `cdroot` and `rootfs` folders - to the primary partition.

Make sure that the following files exist:

- `/boot/kernel64.bin` - the DIOS kernel
- `/boot/rootfs.tar` - RAM filesystem image
- `/boot/limine.conf` - bootloader config
- `/boot/limine-bios.sys` - bootloader binary for BIOS
- `/EFI/BOOT/BOOTX64.EFI` - bootloader binary for UEFI.

At startup, DIOS kernel mounts a bootloader-provided RAM FS image to the filesystem root. To use the system installed on disk, it must mount a volume to the root, for example:

```
rmount /mnt/sata0p1 rw
```

Doing this manually each time is not very convenient, so the kernel allows to automate this process. Add this command to `rootfs/kernel/init.ss`, a kernel shell script that is executed after successfull initializatoin. Then rebuild `rootfs.tar` by running `python build.py rootfs` and put it on the primary partition as `/boot/rootfs.tar`.
