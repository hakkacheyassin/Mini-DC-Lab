#!/bin/bash
#
# 04-deploy-storage.sh  Deploy Storage VM (iSCSI + NFS)
#
set -euo pipefail

UBUNTU_ISO="${UBUNTU_ISO:-/var/lib/libvirt/images/ubuntu-server.iso}"
VM_DIR="/var/lib/libvirt/images"
VM_NAME="storage-vm"
DISK_PATH="$VM_DIR/${VM_NAME}.qcow2"

echo ""
echo "  Mini-DC Lab2  Storage VM Deployment"
echo ""

if [ ! -f "$UBUNTU_ISO" ]; then
  echo "Ubuntu Server ISO not found at: $UBUNTU_ISO"
  echo "   Download Ubuntu Server 22.04/24.04 LTS and place at: $UBUNTU_ISO"
  echo "   Or set UBUNTU_ISO=/path/to/iso"
  exit 1
fi

for net in br0-mgmt br-iscsi; do
  if ! virsh net-info "$net" &>/dev/null; then
    echo "Network '$net' not found. Run 01-network-setup.sh first."
    exit 1
  fi
done

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
  --ram 4096 \
  --vcpus 2 \
  --cpu host-passthrough \
  --os-variant ubuntu22.04 \
  --disk path="$DISK_PATH",format=qcow2,bus=virtio,cache=none \
  --cdrom "$UBUNTU_ISO" \
  --network network=br0-mgmt,model=virtio,mac=52:54:00:a0:00:30 \
  --network network=br-iscsi,model=virtio,mac=52:54:00:c0:00:30 \
  --graphics vnc,listen=0.0.0.0,port=5905 \
  --noautoconsole \
  --boot cdrom,hd

echo ""
echo ""
echo "  Storage VM Created"
echo ""
echo ""
echo "  Name:   $VM_NAME"
echo "  RAM:    4 GB"
echo "  vCPU:   2"
echo "  Disk:   500 GB"
echo "  NIC 1:  br0-mgmt  192.168.100.30"
echo "  NIC 2:  br-iscsi  10.0.1.30"
echo ""
echo "Connect via VNC to install Ubuntu:"
echo "   virsh vncdisplay $VM_NAME"
echo ""
echo "After Ubuntu install, configure:"
echo "  1. Static IPs (see README.md)"
echo "  2. iSCSI target with targetcli"
echo "  3. NFS exports"
