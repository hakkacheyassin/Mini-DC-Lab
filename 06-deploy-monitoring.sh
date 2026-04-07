#!/bin/bash
#
# 06-deploy-monitoring.sh  Deploy Monitoring VM (Grafana + Prometheus)
#
set -euo pipefail

UBUNTU_ISO="${UBUNTU_ISO:-/var/lib/libvirt/images/ubuntu-server.iso}"
VM_DIR="/var/lib/libvirt/images"
VM_NAME="monitoring-vm"
DISK_PATH="$VM_DIR/${VM_NAME}.qcow2"
VNC_PORT=5906

echo ""
echo "  Mini-DC Lab2  Monitoring VM Deployment"
echo ""

if [ ! -f "$UBUNTU_ISO" ]; then
  echo "Ubuntu Server ISO not found at: $UBUNTU_ISO"
  echo "   Or set UBUNTU_ISO=/path/to/iso"
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

echo "[1/2] Creating 50GB disk..."
qemu-img create -f qcow2 "$DISK_PATH" 50G

echo "[2/2] Creating VM..."
virt-install \
  --name "$VM_NAME" \
  --ram 4096 \
  --vcpus 2 \
  --cpu host-passthrough \
  --os-variant ubuntu22.04 \
  --disk path="$DISK_PATH",format=qcow2,bus=virtio,cache=none,boot_order=2 \
  --disk path="$UBUNTU_ISO",device=cdrom,bus=sata,readonly=on,boot_order=1 \
  --network network=br0-mgmt,model=virtio,mac=52:54:00:a0:00:40 \
  --graphics vnc,listen=0.0.0.0,port=${VNC_PORT} \
  --noautoconsole \
  --boot menu=on

echo ""
echo ""
echo "  Monitoring VM Created"
echo ""
echo ""
echo "  Name:   $VM_NAME"
echo "  RAM:    4 GB"
echo "  vCPU:   2"
echo "  Disk:   50 GB"
echo "  NIC:    br0-mgmt 192.168.100.40"
echo ""
echo "Connect via VNC to install Ubuntu:"
echo "   virsh vncdisplay $VM_NAME"
echo "   (fixed port: ${VNC_PORT})"
echo ""
echo "After install, configure:"
echo "  1. Static IP 192.168.100.40/24"
echo "  2. Install Docker"
echo "  3. Deploy Prometheus + Grafana stack"
echo "  (Full instructions in README.md)"
