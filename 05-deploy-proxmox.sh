#!/bin/bash
#
# 05-deploy-proxmox.sh  Deploy Proxmox Backup Server
#
set -euo pipefail

PBS_ISO="${PBS_ISO:-/var/lib/libvirt/images/proxmox-backup-server.iso}"
VM_DIR="/var/lib/libvirt/images"
VM_NAME="proxmox-bs"
DISK_PATH="$VM_DIR/${VM_NAME}.qcow2"

echo ""
echo "  Mini-DC Lab2  Proxmox Backup Server"
echo ""

if [ ! -f "$PBS_ISO" ]; then
  echo "Proxmox Backup Server ISO not found at: $PBS_ISO"
  echo "   Download from: https://www.proxmox.com/en/downloads"
  echo "   Or set PBS_ISO=/path/to/iso"
  exit 1
fi

if ! virsh net-info br0-mgmt &>/dev/null; then
  echo "Network 'br0-mgmt' not found. Run 01-network-setup.sh first."
  exit 1
fi

if virsh dominfo "$VM_NAME" &>/dev/null; then
  echo "VM '$VM_NAME' already exists."
  echo "   To redeploy: virsh destroy $VM_NAME && virsh undefine $VM_NAME --remove-all-storage"
  exit 0
fi

echo "[1/2] Creating 500GB disk..."
qemu-img create -f qcow2 "$DISK_PATH" 500G

echo "[2/2] Creating VM..."
virt-install \
  --name "$VM_NAME" \
  --ram 8192 \
  --vcpus 4 \
  --cpu host-passthrough \
  --os-variant debian11 \
  --disk path="$DISK_PATH",format=qcow2,bus=virtio,cache=none \
  --cdrom "$PBS_ISO" \
  --network network=br0-mgmt,model=virtio,mac=52:54:00:a0:00:50 \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole \
  --boot cdrom,hd

echo ""
echo ""
echo "  Proxmox Backup Server Created"
echo ""
echo ""
echo "  Name:   $VM_NAME"
echo "  RAM:    8 GB"
echo "  vCPU:   4"
echo "  Disk:   500 GB"
echo "  NIC:    br0-mgmt 192.168.100.50"
echo ""
echo "Connect via VNC to install PBS:"
echo "   virsh vncdisplay $VM_NAME"
echo ""
echo "During installation, set:"
echo "  IP:      192.168.100.50/24"
echo "  Gateway: 192.168.100.1"
echo "  DNS:     8.8.8.8"
echo ""
echo "After install https://192.168.100.50:8007"
