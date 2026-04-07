#!/bin/bash
#
# 08-deploy-pfsense.sh  Deploy pfSense Firewall/Router
#
# pfSense acts as the lab's firewall, router, and VLAN gateway.
# WAN = br0-mgmt (gets internet via libvirt NAT)
# LAN = br-lan (internal lab network)
#
set -euo pipefail

PFSENSE_ISO="${PFSENSE_ISO:-/var/lib/libvirt/images/pfSense-CE-2.7.2-RELEASE-amd64.iso}"
VM_DIR="/var/lib/libvirt/images"
VM_NAME="pfsense"
DISK_PATH="$VM_DIR/${VM_NAME}.qcow2"

PF_RAM=1024       # 1 GB
PF_VCPUS=1
PF_DISK="10G"

echo ""
echo "  Mini-DC Lab2  pfSense Firewall/Router"
echo ""

if [ ! -f "$PFSENSE_ISO" ]; then
  echo "pfSense ISO not found at: $PFSENSE_ISO"
  echo ""
  echo "   Download pfSense CE from:"
  echo "   https://www.pfsense.org/download/"
  echo ""
  echo "   Architecture: AMD64 | Installer: DVD Image (ISO)"
  echo "   Or set PFSENSE_ISO=/path/to/iso"
  exit 1
fi

#  Create LAN bridge if not exists 
if ! virsh net-info br-lan &>/dev/null; then
  echo "[0/3] Creating br-lan (LAN  10.10.0.0/24, isolated)..."
cat > /tmp/br-lan.xml << 'EOF'
<network>
  <name>br-lan</name>
  <bridge name='br-lan' stp='on' delay='0'/>
</network>
EOF
  virsh net-define /tmp/br-lan.xml
  virsh net-start br-lan
  virsh net-autostart br-lan
  rm -f /tmp/br-lan.xml
  echo "  br-lan created (pfSense will be the gateway)"
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

# Add DHCP reservation for WAN side
virsh net-update br0-mgmt add ip-dhcp-host \
  "<host mac='52:54:00:a0:00:01' name='$VM_NAME' ip='192.168.100.1'/>" \
  --live --config 2>/dev/null || true

echo "[1/2] Creating ${PF_DISK} disk..."
qemu-img create -f qcow2 "$DISK_PATH" "$PF_DISK"

echo "[2/2] Creating VM..."
virt-install \
  --name "$VM_NAME" \
  --ram $PF_RAM \
  --vcpus $PF_VCPUS \
  --cpu host-passthrough \
  --os-variant freebsd13.0 \
  --disk path="$DISK_PATH",format=qcow2,bus=virtio,cache=none \
  --cdrom "$PFSENSE_ISO" \
  --network network=br0-mgmt,model=virtio,mac=52:54:00:a0:00:01 \
  --network network=br-lan,model=virtio,mac=52:54:00:a0:00:02 \
  --graphics vnc,listen=0.0.0.0 \
  --noautoconsole \
  --boot cdrom,hd

echo ""
echo ""
echo "  pfSense Firewall Created"
echo ""
echo ""
echo "  Name:   $VM_NAME"
echo "  RAM:    1 GB"
echo "  vCPU:   1"
echo "  Disk:   10 GB"
echo "  NIC 1:  br0-mgmt (WAN) 192.168.100.2"
echo "  NIC 2:  br-lan   (LAN) 10.10.0.1 (configured in pfSense)"
echo ""
echo "Connect via VNC to install pfSense:"
echo "   virsh vncdisplay $VM_NAME"
echo ""
echo ""
echo "  During pfSense Install:                             "
echo "  1. Accept defaults, install to disk                 "
echo "  2. After reboot, assign interfaces:                 "
echo "     WAN = vtnet0 (br0-mgmt)                         "
echo "     LAN = vtnet1 (br-lan)                            "
echo "  3. Set WAN IP: 192.168.100.2/24  gw 192.168.100.1  "
echo "  4. Set LAN IP: 10.10.0.1/24                        "
echo "                                                      "
echo "  After install, access Web UI:                       "
echo "  https://192.168.100.2 (admin / pfsense)             "
echo "                                                      "
echo "  Configure VLANs from Web UI:                        "
echo "  Interfaces VLANs Add:                          "
echo "    VLAN 10: Management  (192.168.10.0/24)            "
echo "    VLAN 20: Servers     (192.168.20.0/24)            "
echo "    VLAN 30: Storage     (192.168.30.0/24)            "
echo "    VLAN 40: DMZ         (192.168.40.0/24)            "
echo ""
