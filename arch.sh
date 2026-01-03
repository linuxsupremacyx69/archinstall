#!/bin/bash
set -e

### ===== CONFIG ===== ###
EFI_PART="/dev/nvme0n1p1"
ROOT_PART="/dev/nvme0n1p5"
MNT="/mnt"
HOSTNAME="HyperArch"
USERNAME="notshroudx97"
TIMEZONE="Asia/Kolkata"
LOCALE="en_US.UTF-8"
### =================== ###

echo "==> Mounting root"
mount $ROOT_PART $MNT

echo "==> Mounting EFI"
mount --mkdir $EFI_PART $MNT/boot/efi

echo "==> CLEANING EFI BOOTLOADERS (SAFE)"
rm -rf $MNT/boot/efi/EFI/GRUB
rm -rf $MNT/boot/efi/EFI/Arch
rm -rf $MNT/boot/efi/EFI/systemd
rm -rf $MNT/boot/efi/EFI/Linux

echo "==> Removing broken NVRAM entries"
for entry in $(efibootmgr | grep -i grub | cut -c5-8); do
  efibootmgr -b $entry -B || true
done

echo "==> Entering chroot"
arch-chroot $MNT /bin/bash <<EOF

set -e

echo "==> Time + locale"
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

echo "$HOSTNAME" > /etc/hostname

echo "==> Core packages"
pacman -S --noconfirm \
base linux linux-firmware \
sudo networkmanager \
grub efibootmgr os-prober \
nvidia nvidia-utils nvidia-settings \
hyprland wayland \
xdg-desktop-portal-hyprland \
pipewire pipewire-pulse wireplumber \
kitty wl-clipboard grim slurp \
sddm git curl unzip \
ttf-jetbrains-mono firefox

echo "==> Enable services"
systemctl enable NetworkManager
systemctl enable sddm

echo "==> User creation"
useradd -m -G wheel $USERNAME
echo "$USERNAME ALL=(ALL) ALL" > /etc/sudoers.d/$USERNAME
passwd $USERNAME

echo "==> NVIDIA HARD FIX"
sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash nvidia_drm.modeset=1"/' /etc/default/grub
sed -i 's/#GRUB_DISABLE_OS_PROBER/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

echo "==> Install GRUB (UEFI SAFE MODE)"
grub-install \
--target=x86_64-efi \
--efi-directory=/boot/efi \
--bootloader-id=GRUB \
--recheck

echo "==> Generate GRUB config"
mkdir -p /boot/grub
grub-mkconfig -o /boot/grub/grub.cfg

echo "==> VERIFY normal.mod"
test -f /boot/grub/x86_64-efi/normal.mod || (echo "GRUB MODULE MISSING!" && exit 1)

echo "==> Install Caelestia Shell"
sudo -u $USERNAME bash <<USER
cd ~
git clone https://github.com/caelestia-shell/caelestia.git
cd caelestia
./install.sh
USER

echo "==> Chroot complete"
EOF

echo "==> Unmounting"
umount -R $MNT

echo "✅ DONE — REMOVE USB & REBOOT"
