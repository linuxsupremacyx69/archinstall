#!/usr/bin/env bash
set -e

### ===== USER CONFIG ===== ###
DISK="/dev/nvme0n1"
EFI_PART="/dev/nvme0n1p1"
ROOT_PART="/dev/nvme0n1p5"
SWAP_PART="/dev/nvme0n1p6"   # comment if none
HOSTNAME="hyperarch"
USERNAME="user"
TIMEZONE="Asia/Kolkata"
LOCALE="en_US.UTF-8"
### ======================== ###

echo "==> Mounting partitions"
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount -t vfat "$EFI_PART" /mnt/boot/efi || { echo "EFI mount failed"; exit 1; }

if [[ -b "$SWAP_PART" ]]; then
  swapon "$SWAP_PART"
fi

echo "==> Fixing DNS"
echo "nameserver 1.1.1.1" > /etc/resolv.conf

echo "==> Installing base system"
pacstrap -K /mnt \
base linux linux-firmware sudo \
networkmanager grub efibootmgr os-prober \
git curl wget nano vim \
pipewire pipewire-pulse wireplumber \
hyprland wayland wayland-protocols \
xdg-desktop-portal-hyprland \
mesa lib32-mesa \
nvidia nvidia-utils nvidia-settings \
ttf-dejavu ttf-liberation

genfstab -U /mnt >> /mnt/etc/fstab

echo "==> Entering chroot"
arch-chroot /mnt /bin/bash <<EOF

set -e

echo "==> Time & locale"
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

echo "==> Hostname"
echo "$HOSTNAME" > /etc/hostname
cat <<EOT > /etc/hosts
127.0.0.1 localhost
::1       localhost
127.0.1.1 $HOSTNAME.localdomain $HOSTNAME
EOT

echo "==> Users"
useradd -m -G wheel -s /bin/bash $USERNAME
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

echo "==> Enable services"
systemctl enable NetworkManager

echo "==> NVIDIA kernel params"
sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="nvidia_drm.modeset=1 /' /etc/default/grub

echo "==> Enable os-prober"
sed -i 's/#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

echo "==> Install GRUB (UEFI)"
grub-install \
--target=x86_64-efi \
--efi-directory=/boot/efi \
--bootloader-id=GRUB \
--recheck

echo "==> Generate GRUB config"
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> Done inside chroot"
EOF

echo "==> Final cleanup"
umount -R /mnt
swapoff -a || true

echo "===================================="
echo " INSTALL COMPLETE"
echo " Reboot, remove USB"
echo " GRUB will show Arch + Windows"
echo "===================================="
