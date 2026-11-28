## Kernel Shell Commands

System information:

- `help` - show the command list
- `cpuinfo` - CPU identification and features
- `mem` - physical memory statistics
- `memmap` - show the memory map
- `clock` - clock source and timer status
- `irq` - interrupt controller status
- `irqstat` - interrupt counts per vector
- `pci` - enumerate PCI functions
- `hexdump [-p] ADDR [LEN]` - dump memory (-p: physical address)
- `history` - show recent commands
- `dmesg [N [SKIP]]` - kernel log (last N lines, SKIP lines before the end)

System control:

- `poweroff` or `shutdown` - shut down the computer
- `reboot` - restart the computer
- `crash pf|ud|div|gp` - trigger a CPU exception (kernel halts)

Disk tools:

- `usb` - list USB devices (hubs, keyboards, removable disks...)
- `disk` - show disks and partitions
- `ptable DISK gpt|mbr yes` - new empty partition table (erases the disk's partitions)
- `padd DISK SIZE|rest [esp|data]` - add a partition (SIZE in MiB)
- `pdel N yes` - delete partition `N`
- `ramcopy NAME` - copy the whole RAM file system into the FAT32 volume `/mnt/NAME` (mounted rw)
- `biosinstall DISK [N] yes` - install Limine BIOS boot code (`limine-bios-hdd.bin`)
- `mkfs N [LABEL] yes` - format partition N as FAT32
- `sync` - flush read-write volumes to the disk

Filesystem:

- `cd [DIR]` - changes the current directory
- `mount [N [NAME] [rw]]` - mount partition `N` as `/mnt/NAME`, read-only unless 'rw' (FAT32 only); no args: mount all volumes found (read-only)
- `remount NAME rw|ro` - switch a mounted volume between read-write and read-only
- `umount NAME` - unmount `/NAME`
- `rmount N|NAME|id=ID [rw|ro]` - make partition N (mounted if needed), or /mnt/NAME, or the volume with the given ID the filesystem root. `rmount ramfs` reverts back to the initial RAM FS root. If called without parameters, shows the current root
- `cat PATH` - print a text file
- `append PATH TEXT` - add a line to the file

Programs:

- `programs` - list the programs in `/bin`
- `run NAME [ARGS] [&]` - run a program (`&` = run in background). Plain `NAME` works too
- `ps` - list running programs
- `kill ID` - stop a program
- `fg [ID]` - bring a background program to the foreground

Graphics server:

- `gfx [CMD]` - manage graphics server. CMD can be `status`, `start [NAME]`, `stop`, `show`, `hide`. Requires `gfxd.elf`

Shell control:

- `sleep SECONDS` - wait (Ctrl+C aborts)
- `clear` - clear the screen
