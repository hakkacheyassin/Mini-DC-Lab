#!/bin/bash
#──────────────────────────────────────────────────────────────
# 02-deploy-esxi.sh — Deploy ESXi Host 01 & 02 on KVM
#──────────────────────────────────────────────────────────────
# Both ESXi hosts run as nested VMs on KVM with host-passthrough
# CPU and vmx flag for nested virtualization support.
#──────────────────────────────────────────────────────────────
set -euo pipefail

ESXI_ISO="${ESXI_ISO:-/var/lib/libvirt/images/ESXi-8.iso}"
VM_DIR="/var/lib/libvirt/images"

# ─── Resource allocation (64 GB host total) ───
ESXI_RAM=12288    # 12 GB per host
ESXI_VCPUS=4
ESXI_DISK="100G"

echo "═══════════════════════════════════════════"
echo "  Mini-DC Lab2 — ESXi Deployment (on KVM)"
echo "═══════════════════════════════════════════"

# ─── Pre-checks ───
if [ ! -f "$ESXI_ISO" ]; then
  echo "❌ ESXi ISO not found at: $ESXI_ISO"
  echo "   Download ESXi 8 ISO and place it at: $ESXI_ISO"
  echo "   Or set ESXI_ISO=/path/to/iso before running."
  exit 1
fi

# Check nested virt
if [ "$(cat /sys/module/kvm_intel/parameters/nested 2>/dev/null)" != "Y" ]; then
  echo "⚠️  Nested virtualization not enabled! Enabling now..."
  modprobe -r kvm_intel
  modprobe kvm_intel nested=1 ept=1
  echo "options kvm_intel nested=1 ept=1" > /etc/modprobe.d/kvm-nested.conf
fi

# Check networks exist
for net in br0-mgmt br-vmotion br-iscsi; do
  if ! virsh net-info "$net" &>/dev/null; then
    echo "❌ Network '$net' not found. Run 01-network-setup.sh first."
    exit 1
  fi
done

deploy_esxi() {
  local NAME=$1
  local MAC_MGMT=$2
  local MAC_VMOT=$3
  local MAC_ISCSI=$4
  local DISK_PATH="$VM_DIR/${NAME}.qcow2"

  echo ""
  echo "─── Deploying $NAME ───"

  if virsh dominfo "$NAME" &>/dev/null; then
    echo "  ⏭️  VM '$NAME' already exists, skipping"
    return 0
  fi

  # Create disk
  echo "  [1/2] Creating ${ESXI_DISK} disk..."
  qemu-img create -f qcow2 "$DISK_PATH" "$ESXI_DISK"

  # Create VM
  echo "  [2/2] Defining VM..."
  virt-install \
    --name "$NAME" \
    --ram $ESXI_RAM \
    --vcpus $ESXI_VCPUS,sockets=1,cores=$ESXI_VCPUS,threads=1 \
    --cpu host-passthrough,+vmx \
    --os-variant generic \
    --disk path="$DISK_PATH",format=qcow2,bus=sata,cache=none \
    --cdrom "$ESXI_ISO" \
    --network network=br0-mgmt,model=vmxnet3,mac="$MAC_MGMT" \
    --network network=br-vmotion,model=vmxnet3,mac="$MAC_VMOT" \
    --network network=br-iscsi,model=vmxnet3,mac="$MAC_ISCSI" \
    --graphics vnc,listen=0.0.0.0 \
    --video qxl \
    --noautoconsole \
    --boot cdrom,hd \
    --machine q35 \
    --features kvm_hidden=on \
    --xml xpath.set="./cpu/@mode=host-passthrough"

  echo "  ✅ $NAME created and booting from ISO"
}

# ─── Deploy ESXi Host 01 ───
deploy_esxi "esxi01" \
  "52:54:00:a0:00:10" \
  "52:54:00:b0:00:10" \
  "52:54:00:c0:00:10"

# ─── Deploy ESXi Host 02 ───
deploy_esxi "esxi02" \
  "52:54:00:a0:00:11" \
  "52:54:00:b0:00:11" \
  "52:54:00:c0:00:11"

echo ""
echo "═══════════════════════════════════════════"
echo "  ✅ ESXi Deployment Summary"
echo "═══════════════════════════════════════════"
echo ""
echo "  VM         RAM      vCPU   Disk     MAC (mgmt)"
echo "  ─────────  ──────   ─────  ──────   ─────────────────"
echo "  esxi01     12 GB    4      100 GB   52:54:00:a0:00:10"
echo "  esxi02     12 GB    4      100 GB   52:54:00:a0:00:11"
echo ""
echo "📺 Connect via VNC to complete ESXi installation:"
echo "   virsh vncdisplay esxi01"
echo "   virsh vncdisplay esxi02"
echo ""
echo "After ESXi installs, configure networking via DCUI:"
echo "  ESXi-01: 192.168.100.10/24  gw 192.168.100.1"
echo "  ESXi-02: 192.168.100.11/24  gw 192.168.100.1"
echo ""
echo "⚡ Post-install commands listed in README.md"
