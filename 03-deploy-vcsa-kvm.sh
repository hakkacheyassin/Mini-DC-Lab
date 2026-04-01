#!/bin/bash
#──────────────────────────────────────────────────────────────
# 03-deploy-vcsa-kvm.sh — Deploy vCenter (VCSA) DIRECTLY on KVM
#──────────────────────────────────────────────────────────────
# Deploys vCenter Server Appliance directly on KVM, bypassing
# ESXi entirely. Extracts OVA from ISO, converts VMDKs to
# QCOW2, and injects OVF environment via ISO.
#──────────────────────────────────────────────────────────────
set -euo pipefail

VCSA_ISO="${VCSA_ISO:-/var/lib/libvirt/images/VCSA.iso}"
VCSA_MOUNT="/mnt/vcsa"
KVM_DATASTORE="/var/lib/libvirt/images"
VM_NAME="vcenter01"
VCSA_IP="192.168.100.20"
VCSA_PASS="Hamida1998*/e1337"
SSO_PASS="Hamida1998*/e1337"
VCSA_NET="br0-mgmt"
VCSA_MAC="52:54:00:a0:00:20"

# ─── Resources (KVM-only lab — generous allocation) ───
VCSA_RAM=24576    # 24 GB
VCSA_VCPUS=8

echo "═════════════════════════════════════════════════════════════"
echo "  Deploying vCenter DIRECTLY on KVM (No ESXi Required)"
echo "═════════════════════════════════════════════════════════════"
echo "  RAM: $((VCSA_RAM / 1024)) GB | vCPU: $VCSA_VCPUS | IP: $VCSA_IP"
echo ""

if [ ! -f "$VCSA_ISO" ]; then
  echo "❌ VCSA ISO not found at: $VCSA_ISO"
  echo "   Set VCSA_ISO=/path/to/iso before running."
  exit 1
fi

# Check network exists
if ! virsh net-info "$VCSA_NET" &>/dev/null; then
  echo "❌ Network '$VCSA_NET' not found. Run 01-network-setup.sh first."
  exit 1
fi

echo "[1/5] Mounting VCSA ISO..."
sudo mkdir -p "$VCSA_MOUNT"
if ! mountpoint -q "$VCSA_MOUNT"; then
  sudo mount -o loop "$VCSA_ISO" "$VCSA_MOUNT"
fi

echo "[2/5] Extracting VCSA OVA..."
WORK_DIR="/tmp/vcsa-kvm-build"
sudo rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# Remove old artifacts to avoid reusing corrupted disks/config
sudo rm -f "$KVM_DATASTORE"/${VM_NAME}-disk*.qcow2 "$KVM_DATASTORE/${VM_NAME}-init.iso"

OVA_FILE=$(find "$VCSA_MOUNT/vcsa" -name "*.ova" | head -n 1)
if [ -z "$OVA_FILE" ]; then
  echo "❌ No OVA found in $VCSA_MOUNT/vcsa!"
  exit 1
fi

echo "  > Unpacking $(basename "$OVA_FILE")..."
tar -xf "$OVA_FILE" -C "$WORK_DIR"

# Convert VMDKs to QCOW2 for KVM
echo "[3/5] Converting VMDK disks to QCOW2 (this takes a few minutes)..."
DISK_ID=1
for vmdk in "$WORK_DIR"/*.vmdk; do
  qcow_disk="$KVM_DATASTORE/${VM_NAME}-disk${DISK_ID}.qcow2"
  echo "  > Converting $(basename "$vmdk") → $(basename "$qcow_disk")"
  sudo qemu-img convert -f vmdk -O qcow2 "$vmdk" "$qcow_disk"
  sudo chmod 644 "$qcow_disk"
  DISK_ID=$((DISK_ID + 1))
done

# Create OVF Environment ISO for Photon OS to pick up config
echo "[4/5] Generating OVF Environment ISO..."
cat > "$WORK_DIR/ovf-env.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<Environment
     xmlns="http://schemas.dmtf.org/ovf/environment/1"
     xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
     xmlns:oe="http://schemas.dmtf.org/ovf/environment/1"
     oe:id="vcenter01">
   <PlatformSection>
      <Kind>KVM</Kind>
      <Version>1.0</Version>
      <Vendor>Linux</Vendor>
      <Locale>en</Locale>
   </PlatformSection>
   <PropertySection>
      <Property oe:key="guestinfo.cis.appliance.net.addr.family" oe:value="ipv4"/>
      <Property oe:key="guestinfo.cis.appliance.net.mode" oe:value="static"/>
      <Property oe:key="guestinfo.cis.appliance.net.pnid" oe:value="$VCSA_IP"/>
      <Property oe:key="guestinfo.cis.appliance.net.addr" oe:value="$VCSA_IP"/>
      <Property oe:key="guestinfo.cis.appliance.net.prefix" oe:value="24"/>
      <Property oe:key="guestinfo.cis.appliance.net.gateway" oe:value="192.168.100.1"/>
      <Property oe:key="guestinfo.cis.appliance.net.dns.servers" oe:value="8.8.8.8"/>
      <Property oe:key="guestinfo.cis.appliance.root.passwd" oe:value="$VCSA_PASS"/>
      <Property oe:key="guestinfo.cis.appliance.ssh.enabled" oe:value="True"/>
      <Property oe:key="guestinfo.cis.appliance.ntp.servers" oe:value="pool.ntp.org"/>
      <Property oe:key="guestinfo.cis.vmdir.password" oe:value="$SSO_PASS"/>
      <Property oe:key="guestinfo.cis.vmdir.domain-name" oe:value="vsphere.local"/>
      <Property oe:key="guestinfo.cis.deployment.autoconfig" oe:value="True"/>
      <Property oe:key="guestinfo.cis.ceip_enabled" oe:value="False"/>
   </PropertySection>
</Environment>
EOF

genisoimage -J -R -V "OVF ENV" -o "$KVM_DATASTORE/${VM_NAME}-init.iso" "$WORK_DIR/ovf-env.xml"

# Destroy old VM if it exists
sudo virsh destroy "$VM_NAME" 2>/dev/null || true
sudo virsh undefine "$VM_NAME" --nvram 2>/dev/null || true

echo "[5/5] Deploying KVM Virtual Machine..."

# Build disk arguments dynamically
DISK_ARGS=()
for qcow in "$KVM_DATASTORE"/${VM_NAME}-disk*.qcow2; do
  DISK_ARGS+=(--disk "path=$qcow,bus=sata")
done

sudo virt-install \
  --name "$VM_NAME" \
  --ram $VCSA_RAM \
  --vcpus $VCSA_VCPUS \
  --cpu host-passthrough \
  --machine q35 \
  --boot uefi \
  --os-variant=generic \
  --features kvm_hidden=on \
  --network network=$VCSA_NET,model=e1000,mac=${VCSA_MAC} \
  "${DISK_ARGS[@]}" \
  --disk path="$KVM_DATASTORE/${VM_NAME}-init.iso",device=cdrom \
  --graphics vnc,listen=0.0.0.0 \
  --import \
  --noautoconsole

echo ""
echo "═════════════════════════════════════════════════════════════"
echo "  ✅ vCenter Server deployed on KVM!"
echo "═════════════════════════════════════════════════════════════"
echo ""
echo "  VM:    $VM_NAME"
echo "  RAM:   $((VCSA_RAM / 1024)) GB"
echo "  vCPU:  $VCSA_VCPUS"
echo "  IP:    $VCSA_IP"
echo ""
echo "  ⏳ Wait 10-15 minutes for initialization."
echo "  📺 Monitor:  virsh console $VM_NAME"
echo "  🔧 VAMI:     https://$VCSA_IP:5480"
echo "  🌐 vSphere:  https://$VCSA_IP"
echo "  👤 Login:    administrator@vsphere.local"
