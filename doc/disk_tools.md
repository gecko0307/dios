# Kernel Disk Tools

If the SATA disk is already in use, unmount it:

```
umount sata0p1
```

Create a new empty partition table (erases the disk's partitions):

```
ptable sata0 gpt yes
```

Add two partitions: `sata0p1` - BIOS boot partition without a filesystem, and `sata0p2` - primary FAT32 partition.

```
padd sata0 bios
padd sata0 rest esp
mkfs 1 DIOS yes
```

Install the BIOS bootloader to the boot partition:

```
biosinstall sata0 yes
```

Mount the primary partition:

```
mount 1 sata0p2 rw
```

Install the system to the primary partition:

```
ramcopy sata0p2
```

Make it the root:

```
rmount sata0p2 rw
```

Remove the boot media (CD/USB) and reboot:

```
reboot
```
