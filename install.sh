#!/usr/bin/env bash

# Get the correct location for this file.
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )

set -x # Echo each command executed
set -eo pipefail # Exit if any command fails. Print command.

# Execute commands from the correct folder.
cd

# --- Partitioning
disk="/dev/nvme0n1"
efi_part="$disk"p1
linux_part="$disk"p2

btrfs_label="arch_btrfs"

swap_size=10g

hostname=macbook_pro
username=openbsd

# TODO: Add option to remove ssd if using hdd
mount_options="noatime,compress=zstd,ssd,commit=120"

# Set the partitions to be wiped
sgdisk -og -n 1:4096:+2G -c 1:${efi_part_name} -t 1:ef00 -n 2:0:0 -c 2:${linux_part_name} -t 2:8300 -p "$disk"
# --- Done Partitioning

# --- Creating Filesystems
mkfs.vfat -I -F32 "$efi_part"
mkfs.btrfs -f "$linux_part" -L "$btrfs_label"

mount --mkdir "$linux_part" /mnt/arch

btrfs subvolume create /mnt/arch/@
btrfs subvolume create /mnt/arch/@home
btrfs subvolume create /mnt/arch/@log
btrfs subvolume create /mnt/arch/@tmp
btrfs subvolume create /mnt/arch/@pkg
btrfs subvolume create /mnt/arch/@.snapshots

# btrfs subvolume create /mnt/arch/@swap

umount /mnt/arch

mount -m -o ${mount_options},subvol=@ "$linux_part" /mnt/arch
mount -m -o ${mount_options},subvol=@home "$linux_part" /mnt/arch/home
mount -m -o ${mount_options},subvol=@pkg "$linux_part" /mnt/arch/var/cache/pacman/pkg
mount -m -o ${mount_options},subvol=@log "$linux_part" /mnt/arch/var/log
mount -m -o ${mount_options},subvol=@tmp "$linux_part" /mnt/arch/var/tmp
mount -m -o ${mount_options},subvol=@.snapshots "$linux_part" /mnt/arch/.snapshots

# mount -m -o subvol=@swap "$linux_part" /mnt/arch/swap

# btrfs filesystem mkswapfile --size "$swap_size" --uuid clear /mnt/arch/swap/swapfile
# swapon /mnt/arch/swap/swapfile

btrfs subvolume list -a /mnt/arch

mount -m -o defaults,noatime "$efi_part" /mnt/arch/boot

# Create /var/lib/machines and /var/lib/portables
# So that systemd will not create them as nested subvolumes
mkdir -p /mnt/arch/var/lib/machines
mkdir -p /mnt/arch/var/lib/portables

# --- Done Filesystems

proc_type=$(lscpu)
if grep -E "GenuineIntel" <<< ${proc_type}; then
    micro_code=intel-ucode
elif grep -E "AuthenticAMD" <<< ${proc_type}; then
    micro_code=amd-ucode
fi

essential_pkg=$(awk -F '#' 'BEGIN{OFS="#";} { if (!/#/) ;else $NF="";print $0}' test.txt | sed -n 's/#$//g;p' | grep -v "^$" | tr '\n' ' ' < "${DIR}/pacstrap_essential.txt")


# Update keyring to allow downloading packages
pacman -Sy --noconfirm archlinux-keyring

# Set installer keymap to UK
#v/usr/bin/localectl set-keymap uk

# Update the mirrorlist
reflector \
        --country GB,France,Germany \
        --age 12 \
        --protocol https \
        --fastest 5 \
        --latest 20 \
        --sort rate \
        --save /etc/pacman.d/mirrorlist

pacman -Syy

pacstrap -K /mnt/arch ${essential_pkg} ${micro_code} --noconfirm --needed

cp -r -t /mnt/arch/etc/systemd/ /etc/systemd/network* /etc/systemd/resolved*
genfstab -L /mnt/arch >> /mnt/arch/etc/fstab

# Remove subvolid to avoid problems with restoring snapper snapshots
sed -i 's/subvolid=.*,//' /mnt/arch/etc/fstab
echo $(arch-chroot /mnt/arch chmod 700 /root)

mkdir -p /mnt/arch/boot/EFI/BOOT

echo $(arch-chroot /mnt/arch pacman -Syu --noconfirm --needed)

echo $(arch-chroot /mnt/arch bootctl install)
echo -e \
"default  @saved
timeout  1
editor   0" >> /mnt/arch/boot/loader/loader.conf

touch /mnt/arch/boot/loader/entries/arch.conf
touch /mnt/arch/boot/loader/entries/arch-fallback.conf

arch_UUID=$(blkid -s UUID -o value ${linux_part})

echo -e \
"title   Arch Linux
linux   /vmlinuz-linux-zen
initrd  /${micro_code}.img
initrd  /initramfs-linux-zen.img
options root=LABEL=${btrfs_label} rootflags=subvol=@ rw rootfstype=btrfs" \ 
  >> /mnt/arch/boot/loader/entries/arch.conf

echo -e \ 
"title   Arch Linux (fallback initramfs)
linux   /vmlinuz-linux-zen
initrd  /${micro_code}.img
initrd  /initramfs-linux-zen-fallback.img
options root=LABEL=${btrfs_label} rootflags=subvol=@ rw rootfstype=btrfs" >> /mnt/arch/boot/loader/entries/arch-fallback.conf

ln -sf /mnt/arch/usr/share/zoneinfo/Europe/London /mnt/arch/etc/localtime
echo $(arch-chroot /mnt/arch hwclock --systohc)
echo -e "en_US.UTF-8 UTF-8" >> /mnt/arch/etc/locale.gen
echo $(arch-chroot /mnt/arch locale-gen)
echo "LANG=en_US.UTF-8" >> /mnt/arch/etc/locale.conf
echo "KEYMAP=us" >> /mnt/arch/etc/vconsole.conf
echo "$hostname" >> /mnt/arch/etc/hostname
touch /mnt/arch/etc/hosts
echo -e "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 ${hostname}" >> /mnt/arch/etc/hosts

echo $(arch-chroot /mnt/arch mkinitcpio -P)
echo $(arch-chroot /mnt/arch systemctl enable systemd-networkd)
echo $(arch-chroot /mnt/arch systemctl enable systemd-resolved)
echo $(arch-chroot /mnt/arch systemctl enable systemd-resolved)

echo $(arch-chroot /mnt/arch useradd -m ${username})

echo $(arch-chroot /mnt/arch usermod -aG sys,wheel,audio,input,uucp,rfkill,plugdev ${username})

sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /mnt/arch/etc/sudoers

echo $(arch-chroot /mnt/arch timedatectl set-ntp true)

echo "COMPLETED!!!!!"
echo "IMPORTANT: remember to set the password in the end!"
