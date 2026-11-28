umount
ptable sata0 gpt yes
padd sata0 bios
padd sata0 rest esp
mkfs 1 DIOS yes
biosinstall sata0 yes
mount 1 sata0p2 rw
ramcopy sata0p2
touch /mnt/sata0p2/boot/dios.here
rm /mnt/sata0p2/install.ss
echo Done!
