#!/bin/bash
#
# 01-network-setup.sh  Create bridge networks for KVM-only lab
#
# All VMs (including ESXi) run directly on KVM
# Three bridges: management, vMotion, iSCSI
#
set -euo pipefail

echo ""
echo "  Mini-DC Lab2  Network Setup (KVM-Only)"
echo ""

#  br0-mgmt: Management Network (192.168.100.0/24) with NAT 
echo "[1/3] Creating br0-mgmt (Management  192.168.100.0/24)..."
if ! virsh net-info br0-mgmt &>/dev/null; then
cat > /tmp/br0-mgmt.xml << 'EOF'
<network>
  <name>br0-mgmt</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='br0' stp='on' delay='0'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.100.100' end='192.168.100.199'/>
      <!-- Static reservations for lab VMs -->
      <host mac='52:54:00:a0:00:10' name='esxi01' ip='192.168.100.10'/>
      <host mac='52:54:00:a0:00:11' name='esxi02' ip='192.168.100.11'/>
      <host mac='52:54:00:a0:00:20' name='vcenter01' ip='192.168.100.20'/>
      <host mac='52:54:00:a0:00:30' name='storage' ip='192.168.100.30'/>
      <host mac='52:54:00:a0:00:40' name='monitor' ip='192.168.100.40'/>
      <host mac='52:54:00:a0:00:50' name='proxmox' ip='192.168.100.50'/>
    </dhcp>
  </ip>
</network>
EOF
  virsh net-define /tmp/br0-mgmt.xml
  virsh net-start br0-mgmt
  virsh net-autostart br0-mgmt
  rm -f /tmp/br0-mgmt.xml
  echo "  br0-mgmt created and started"
else
  echo "  br0-mgmt already exists, skipping"
fi

#  br-vmotion: vMotion Network (10.0.0.0/24) 
echo "[2/3] Creating br-vmotion (vMotion  10.0.0.0/24)..."
if ! virsh net-info br-vmotion &>/dev/null; then
cat > /tmp/br-vmotion.xml << 'EOF'
<network>
  <name>br-vmotion</name>
  <bridge name='br-vmotion' stp='on' delay='0'/>
  <ip address='10.0.0.1' netmask='255.255.255.0'/>
</network>
EOF
  virsh net-define /tmp/br-vmotion.xml
  virsh net-start br-vmotion
  virsh net-autostart br-vmotion
  rm -f /tmp/br-vmotion.xml
  echo "  br-vmotion created and started"
else
  echo "  br-vmotion already exists, skipping"
fi

#  br-iscsi: iSCSI Storage Network (10.0.1.0/24) 
echo "[3/3] Creating br-iscsi (iSCSI  10.0.1.0/24)..."
if ! virsh net-info br-iscsi &>/dev/null; then
cat > /tmp/br-iscsi.xml << 'EOF'
<network>
  <name>br-iscsi</name>
  <bridge name='br-iscsi' stp='on' delay='0'/>
  <ip address='10.0.1.1' netmask='255.255.255.0'/>
</network>
EOF
  virsh net-define /tmp/br-iscsi.xml
  virsh net-start br-iscsi
  virsh net-autostart br-iscsi
  rm -f /tmp/br-iscsi.xml
  echo "  br-iscsi created and started"
else
  echo "  br-iscsi already exists, skipping"
fi

#  Verify 
echo ""
echo ""
echo "  Network Summary"
echo ""
virsh net-list --all
echo ""
echo "Management (br0-mgmt  192.168.100.0/24 NAT):"
echo "  .10 esxi01  |  .11 esxi02  |  .20 vcenter01"
echo "  .30 storage |  .40 monitor |  .50 proxmox"
echo ""
echo "vMotion  (br-vmotion  10.0.0.0/24 isolated)"
echo "iSCSI    (br-iscsi    10.0.1.0/24 isolated)"
echo ""
echo "All networks configured!"
