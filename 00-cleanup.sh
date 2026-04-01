#!/bin/bash
#──────────────────────────────────────────────────────────────
# 00-cleanup.sh — Destroy ALL VMs, networks, and disk images
#──────────────────────────────────────────────────────────────
# ⚠️  This wipes EVERYTHING on the KVM host. No data is preserved.
#──────────────────────────────────────────────────────────────
set -euo pipefail

echo "═══════════════════════════════════════════════════════"
echo "  ⚠️  Mini-DC Lab2 — FULL CLEANUP"
echo "  This will destroy ALL VMs, networks, and images."
echo "═══════════════════════════════════════════════════════"
echo ""

# Safety prompt
read -p "Are you sure you want to wipe everything? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "❌ Aborted."
  exit 1
fi

# ─── Destroy all VMs ───
echo ""
echo "[1/4] Destroying all KVM VMs..."
for vm in $(virsh list --all --name 2>/dev/null); do
  if [ -n "$vm" ]; then
    echo "  → Stopping: $vm"
    virsh destroy "$vm" 2>/dev/null || true
    echo "  → Removing: $vm (with storage)"
    virsh undefine "$vm" --remove-all-storage --nvram 2>/dev/null || \
    virsh undefine "$vm" --remove-all-storage 2>/dev/null || true
  fi
done
echo "  ✅ All VMs destroyed"

# ─── Remove custom networks ───
echo ""
echo "[2/4] Removing custom libvirt networks..."
for net in br0-mgmt br-vmotion br-iscsi; do
  if virsh net-info "$net" &>/dev/null; then
    echo "  → Stopping: $net"
    virsh net-destroy "$net" 2>/dev/null || true
    echo "  → Undefining: $net"
    virsh net-undefine "$net" 2>/dev/null || true
  else
    echo "  → $net not found, skipping"
  fi
done
echo "  ✅ Custom networks removed"

# ─── Clean disk images ───
echo ""
echo "[3/4] Cleaning disk images..."
IMG_DIR="/var/lib/libvirt/images"
if [ -d "$IMG_DIR" ]; then
  # Remove qcow2 and iso files created by our scripts
  find "$IMG_DIR" -maxdepth 1 \( -name "*.qcow2" -o -name "*-init.iso" \) -print -delete 2>/dev/null || true
  echo "  ✅ Disk images cleaned from $IMG_DIR"
else
  echo "  → $IMG_DIR not found, skipping"
fi

# ─── Unmount VCSA ISO if mounted ───
echo ""
echo "[4/4] Cleaning up mounts..."
if mountpoint -q /mnt/vcsa 2>/dev/null; then
  umount /mnt/vcsa
  echo "  ✅ Unmounted /mnt/vcsa"
else
  echo "  → /mnt/vcsa not mounted, skipping"
fi
rm -rf /tmp/vcsa-kvm-build 2>/dev/null || true

# ─── Verify clean state ───
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Cleanup Verification"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "VMs remaining:"
virsh list --all
echo ""
echo "Networks remaining:"
virsh net-list --all
echo ""
echo "Disk images in $IMG_DIR:"
ls -lh "$IMG_DIR"/*.qcow2 2>/dev/null || echo "  (none)"
echo ""
echo "✅ Cleanup complete! Ready for fresh deployment."
