# Kernel Disk Tools

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

rmount id=0319-1D1F rw
