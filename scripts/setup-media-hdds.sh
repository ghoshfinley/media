#!/usr/bin/env bash
# One-time host setup: wipe, format (ext4), and mount the two USB HDDs that serve
# as the media backbone.
#
#   HDD-A -> /mnt/library    (movies + tv)      — playback reads
#   HDD-B -> /mnt/downloads  (torrent scratch)  — random writes
#
# The split is deliberate: keeping torrent write churn on a separate spindle from the
# library means playback stays smooth while downloading. Trade-off: imports become
# copies (no hardlinks) and actively-seeding files cost 2x space (fine on a 3TB disk).
#
# Both drives sit behind one ASMedia USB bridge; addressed by stable by-id path here,
# then mounted by filesystem UUID in /etc/fstab.
#
# Run once:  sudo bash scripts/setup-media-hdds.sh
set -euo pipefail

PUID=1000
PGID=1000

LIB_DEV=/dev/disk/by-id/usb-ASMT_USB_3.0_Destop_H_00000000000000000000-0:0
DL_DEV=/dev/disk/by-id/usb-ASMT_USB_3.0_Destop_H_00000000000000000000-0:1

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo bash $0"; exit 1; }

setup_disk() {
  local dev="$1" label="$2" mnt="$3"
  local real; real="$(readlink -f "$dev")"
  echo "==> $label: $dev -> $real ($mnt)"
  [ -b "$dev" ] || { echo "  !! $dev is not a block device — aborting"; exit 1; }

  # Safety: refuse if the disk (or any partition) is currently mounted.
  if lsblk -no MOUNTPOINT "$real" | grep -q .; then
    echo "  !! $real has something mounted — refusing to wipe"; exit 1
  fi
  # Safety: expect a ~3TB disk (guards against grabbing the wrong device).
  local bytes; bytes=$(blockdev --getsize64 "$real")
  if [ "$bytes" -lt 2500000000000 ] || [ "$bytes" -gt 3200000000000 ]; then
    echo "  !! $real is $bytes bytes, not ~3TB — refusing"; exit 1
  fi

  wipefs -a "$real"
  parted -s "$real" mklabel gpt
  parted -s "$real" mkpart primary ext4 0% 100%
  partprobe "$real"; sleep 2

  local part="${dev}-part1"
  [ -b "$part" ] || part="${real}1"
  mkfs.ext4 -F -L "$label" "$part"

  mkdir -p "$mnt"
  local uuid; uuid=$(blkid -s UUID -o value "$part")
  sed -i "\#[[:space:]]$mnt[[:space:]]#d" /etc/fstab
  echo "UUID=$uuid  $mnt  ext4  defaults,nofail,x-systemd.device-timeout=10  0  2" >> /etc/fstab
  echo "  fstab: UUID=$uuid -> $mnt"
}

setup_disk "$LIB_DEV" media-library   /mnt/library
setup_disk "$DL_DEV"  media-downloads /mnt/downloads

systemctl daemon-reload || true
mount -a

# Library subdirs + ownership (containers run as PUID:PGID).
mkdir -p /mnt/library/movies /mnt/library/tv
chown "$PUID:$PGID" /mnt/library /mnt/library/movies /mnt/library/tv /mnt/downloads
chmod 775 /mnt/library /mnt/library/movies /mnt/library/tv /mnt/downloads

echo
echo "==> Done. Mounts:"
findmnt /mnt/library /mnt/downloads
