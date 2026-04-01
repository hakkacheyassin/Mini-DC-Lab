#!/bin/bash
#──────────────────────────────────────────────────────────────
# 07-deploy-winserver.sh — Deploy Windows Server 2022 (AD + DNS)
#──────────────────────────────────────────────────────────────
# Active Directory Domain Controller + DNS Server for lab.local
# All lab VMs will use this as their DNS server.
#──────────────────────────────────────────────────────────────
set -euo pipefail

WIN_ISO="${WIN_ISO:-/var/lib/libvirt/images/windows-server-2022.iso}"
VIRTIO_ISO="${VIRTIO_ISO:-/var/lib/libvirt/images/virtio-win.iso}"
VM_DIR="/var/lib/libvirt/images"
VM_NAME="win-ad-dns"
DISK_PATH="$VM_DIR/${VM_NAME}.qcow2"

WIN_RAM=4096      # 4 GB
WIN_VCPUS=2
WIN_DISK="80G"

echo "═══════════════════════════════════════════"
echo "  Mini-DC Lab2 — Windows Server (AD + DNS)"
echo "═══════════════════════════════════════════"

if [ ! -f "$WIN_ISO" ]; then
  echo "❌ Windows Server ISO not found at: $WIN_ISO"
  echo ""
  echo "   Download Windows Server 2022 Evaluation from:"
  echo "   https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022"
  echo ""
  echo "   Or set WIN_ISO=/path/to/iso"
  exit 1
fi

# Auto-download VirtIO drivers if missing
if [ ! -f "$VIRTIO_ISO" ]; then
  echo "⚠️  VirtIO drivers ISO not found. Downloading..."
  wget -q --show-progress -O "$VIRTIO_ISO" \
    "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso" || {
    echo "❌ Download failed. Get it from: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
    exit 1
  }
  echo "  ✅ VirtIO drivers downloaded"
fi

if ! virsh net-info br0-mgmt &>/dev/null; then
  echo "❌ Network 'br0-mgmt' not found. Run 01-network-setup.sh first."
  exit 1
fi

if virsh dominfo "$VM_NAME" &>/dev/null; then
  echo "⏭️  VM '$VM_NAME' already exists."
  echo "   To redeploy: virsh destroy $VM_NAME && virsh undefine $VM_NAME --remove-all-storage"
  exit 0
fi

# Add DHCP reservation
virsh net-update br0-mgmt add ip-dhcp-host \
  "<host mac='52:54:00:a0:00:60' name='$VM_NAME' ip='192.168.100.60'/>" \
  --live --config 2>/dev/null || true

echo "[1/2] Creating ${WIN_DISK} disk..."
qemu-img create -f qcow2 "$DISK_PATH" "$WIN_DISK"

echo "[2/2] Creating VM..."
virt-install \
  --name "$VM_NAME" \
  --ram $WIN_RAM \
  --vcpus $WIN_VCPUS \
  --cpu host-passthrough \
  --os-variant win2k22 \
  --disk path="$DISK_PATH",format=qcow2,bus=virtio,cache=none \
  --cdrom "$WIN_ISO" \
  --disk path="$VIRTIO_ISO",device=cdrom \
  --network network=br0-mgmt,model=virtio,mac=52:54:00:a0:00:60 \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole \
  --boot cdrom,hd

echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ Windows Server VM Created"
echo "═══════════════════════════════════════════"
echo ""
echo "  Name:   $VM_NAME"
echo "  RAM:    4 GB"
echo "  vCPU:   2"
echo "  Disk:   80 GB"
echo "  NIC:    br0-mgmt → 192.168.100.60"
echo ""
echo "📺 Connect via VNC to install Windows:"
echo "   virsh vncdisplay $VM_NAME"
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│  During Windows Install:                            │"
echo "│  1. Choose 'Desktop Experience' (not Core)          │"
echo "│  2. Disk not found? Load Driver → virtio CD         │"
echo "│     → browse to: amd64\\w2k22                       │"
echo "│  3. Set Administrator password                      │"
echo "└─────────────────────────────────────────────────────┘"
