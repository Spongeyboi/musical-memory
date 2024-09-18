#!/usr/bin/env bash

swapoff -a

umount /mnt/arch/var/tmp
umount /mnt/arch/var/log
umount /mnt/arch/cache/pacman/pkg
umount /mnt/arch/var/cache/pacman/pkg
umount /mnt/arch/.snapshots
umount /mnt/arch/boot
umount /mnt/arch/swap
umount /mnt/arch/home
umount /mnt/arch/


echo $(./h.sh)

