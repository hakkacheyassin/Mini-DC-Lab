#  Mini-DC Lab2 — Complete Deployment Guide

> **Bare-metal VM**: 64 GB RAM · 3 TB Disk · KVM/QEMU on Ubuntu  
> Everything runs as KVM VMs inside a single physical machine.  
> **vCenter runs DIRECTLY on KVM** — not nested inside ESXi.

---

## 📋 Resource Allocation Plan

| VM | Role | RAM | vCPU | Disk | IP |
|---|---|---|---|---|---|
| Ubuntu Host | KVM Hypervisor | 4 GB (reserved) | — | — | Host OS |
| **pfSense** | Firewall / Router | 1 GB | 1 | 10 GB | 192.168.100.2 |
| ESXi Host 01 | Hypervisor | 12 GB | 4 | 100 GB | 192.168.100.10 |
| ESXi Host 02 | Hypervisor | 12 GB | 4 | 100 GB | 192.168.100.11 |
| vCenter Server 8 | Orchestration (KVM) | 24 GB | 8 | ~600 GB | 192.168.100.20 |
| Storage VM | iSCSI + NFS | 4 GB | 2 | 500 GB | 192.168.100.30 |
| Monitoring VM | Grafana + Prometheus | 4 GB | 2 | 50 GB | 192.168.100.40 |
| Proxmox BS | Backup | 8 GB | 4 | 500 GB | 192.168.100.50 |
| **Windows AD** | Active Directory + DNS | 4 GB | 2 | 80 GB | 192.168.100.60 |

**Total Allocated**: ~69 GB RAM / ~1,940 GB Disk (KVM overcommit handles the RAM)

---

##  Network Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Ubuntu KVM Host (64 GB / 3 TB)                              │
│                                                              │
│  br0-mgmt (192.168.100.1/24)  ─── NAT to Internet           │
│   │                                                          │
│   ├── pfSense   (.2)   ◄── Firewall / Router / VLANs        │
│   ├── ESXi-01   (.10)  ◄── Hypervisor (nested KVM)           │
│   ├── ESXi-02   (.11)  ◄── Hypervisor (nested KVM)           │
│   ├── vCenter   (.20)  ◄── Direct on KVM (NOT on ESXi)       │
│   ├── Storage   (.30)  ◄── iSCSI + NFS targets               │
│   ├── Monitor   (.40)  ◄── Grafana + Prometheus              │
│   ├── Proxmox   (.50)  ◄── Backup server                    │
│   └── Win AD    (.60)  ◄── Active Directory + DNS            │
│                                                              │
│  br-vmotion (10.0.0.0/24) ─── vMotion traffic (isolated)    │
│   ├── ESXi-01   (10.0.0.10)                                 │
│   └── ESXi-02   (10.0.0.11)                                 │
│                                                              │
│  br-iscsi (10.0.1.0/24) ─── Storage traffic (isolated)      │
│   ├── ESXi-01   (10.0.1.10)                                 │
│   ├── ESXi-02   (10.0.1.11)                                 │
│   └── Storage   (10.0.1.30)                                 │
│                                                              │
│  br-lan (10.10.0.0/24) ─── pfSense LAN (for VLANs)          │
│   └── pfSense   (10.10.0.1) ◄── LAN gateway                 │
└──────────────────────────────────────────────────────────────┘
```

> **Key difference from traditional labs**: vCenter is deployed directly as a KVM VM (OVA → QCOW2 conversion), bypassing nested ESXi entirely. This avoids the soft-lockup kernel panics common with deeply nested virtualization.

---

##  Quick Start (Full Deploy)

```bash
# SSH into the host
gcloud compute ssh --zone europe-west1-b mini-dc-lab2

# Deploy everything in one shot
sudo bash scripts/deploy-all.sh

# Or skip cleanup if re-deploying
sudo bash scripts/deploy-all.sh --skip-cleanup
```

---

## 🔧 Phase 0 — Cleanup (Fresh Start)

Run: `sudo bash scripts/00-cleanup.sh`

This destroys ALL existing VMs, networks, and disk images. Interactive confirmation required.

---

## 🔧 Phase 1 — Host Prerequisites

```bash
# Required packages
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients \
  bridge-utils virtinst virt-manager genisoimage curl wget net-tools

# Enable nested virtualization (CRITICAL for ESXi VMs)
echo "options kvm_intel nested=1 ept=1" | sudo tee /etc/modprobe.d/kvm-nested.conf
sudo modprobe -r kvm_intel && sudo modprobe kvm_intel

# Verify nested virt is ON
cat /sys/module/kvm_intel/parameters/nested   # Must show "Y"
```

---

## 🔧 Phase 2 — Network Bridges

Run: `sudo bash scripts/01-network-setup.sh`

Creates three bridges:
- **br0-mgmt** — Management (192.168.100.0/24, NAT to internet)
- **br-vmotion** — vMotion traffic (10.0.0.0/24, isolated)
- **br-iscsi** — iSCSI storage traffic (10.0.1.0/24, isolated)

---

## 🖥️ Phase 3 — Deploy ESXi Hosts

> **Prerequisite**: Download VMware ESXi 8 ISO → `/var/lib/libvirt/images/ESXi-8.iso`

Run: `sudo bash scripts/02-deploy-esxi.sh`

Creates two nested ESXi VMs with:
- CPU host-passthrough + `vmx` flag (nested virt)
- SATA disk controller
- Three NICs: management, vMotion, iSCSI

### Post-boot ESXi Configuration

After both ESXi VMs boot from the ISO and install, configure each via DCUI or SSH:

**ESXi Host 01** (192.168.100.10):
```bash
esxcli network ip interface ipv4 set -i vmk0 -I 192.168.100.10 -N 255.255.255.0 -g 192.168.100.1 -t static
esxcli network ip dns server add --server=8.8.8.8
esxcli system hostname set --fqdn=esxi01.lab.local

# Create vMotion and iSCSI standard switches/portgroups
esxcli network vswitch standard add -v vSwitch1
esxcli network vswitch standard uplink add -v vSwitch1 -u vmnic1
esxcli network vswitch standard portgroup add -p "vMotion" -v vSwitch1

esxcli network vswitch standard add -v vSwitch2
esxcli network vswitch standard uplink add -v vSwitch2 -u vmnic2
esxcli network vswitch standard portgroup add -p "iSCSI" -v vSwitch2

# vMotion VMkernel
esxcli network ip interface add -i vmk1 -p "vMotion"
esxcli network ip interface ipv4 set -i vmk1 -I 10.0.0.10 -N 255.255.255.0 -t static

# iSCSI VMkernel
esxcli network ip interface add -i vmk2 -p "iSCSI"
esxcli network ip interface ipv4 set -i vmk2 -I 10.0.1.10 -N 255.255.255.0 -t static

export GOVC_PASSWORD='Hamida1998*/e1337'

# Enable SSH & Shell
vim-cmd hostsvc/enable_ssh
vim-cmd hostsvc/start_ssh
vim-cmd hostsvc/enable_esx_shell
vim-cmd hostsvc/start_esx_shell
govc host.add -hostname=esxi01.lab.local -username=root -password='Hamida1998*/e1337' -noverify

```

**ESXi Host 02** (192.168.100.11):
```bash
esxcli network ip interface ipv4 set -i vmk0 -I 192.168.100.11 -N 255.255.255.0 -g 192.168.100.1 -t static
esxcli network ip dns server add --server=8.8.8.8
esxcli system hostname set --fqdn=esxi02.lab.local

esxcli network vswitch standard add -v vSwitch1
esxcli network vswitch standard uplink add -v vSwitch1 -u vmnic1
esxcli network vswitch standard portgroup add -p "vMotion" -v vSwitch1

esxcli network vswitch standard add -v vSwitch2
esxcli network vswitch standard uplink add -v vSwitch2 -u vmnic2
esxcli network vswitch standard portgroup add -p "iSCSI" -v vSwitch2

esxcli network ip interface add -i vmk1 -p "vMotion"
esxcli network ip interface ipv4 set -i vmk1 -I 10.0.0.11 -N 255.255.255.0 -t static

esxcli network ip interface add -i vmk2 -p "iSCSI"
esxcli network ip interface ipv4 set -i vmk2 -I 10.0.1.11 -N 255.255.255.0 -t static

vim-cmd hostsvc/enable_ssh
vim-cmd hostsvc/start_ssh
vim-cmd hostsvc/enable_esx_shell
vim-cmd hostsvc/start_esx_shell
```

---

## ☁️ Phase 4 — Deploy vCenter Server 8 (Direct on KVM)

> **Prerequisite**: Download VCSA 8 ISO → `/var/lib/libvirt/images/VMware-VCSA-all-8.0.2-23504390.iso`

Run: `sudo bash scripts/03-deploy-vcsa-kvm.sh`

This script:
1. Mounts the VCSA ISO and extracts the OVA
2. Converts VMDK disks to QCOW2 (native KVM format)
3. Generates an OVF environment ISO with network/password config
4. Creates a KVM VM with 24 GB RAM / 8 vCPU

### Post-Deploy vCenter Setup

1. Wait 10-15 minutes for first boot and services to initialize
2. VAMI: `https://192.168.100.20:5480`
3. vSphere Client: `https://192.168.100.20`
4. Login: `administrator@vsphere.local`

**Via vSphere Client (Web UI):**
```
1. Create Datacenter:     "MiniDC-Lab"
2. Create Cluster:        "HA-Cluster" (Enable HA + DRS)
3. Add Host → ESXi-01:   192.168.100.10
4. Add Host → ESXi-02:   192.168.100.11
5. Configure vMotion:     Select vmk1 on each host → Tag for vMotion
6. Configure HA:          Cluster → Configure → vSphere HA → Enable
7. Configure DRS:         Cluster → Configure → vSphere DRS → Fully Automated
```

---

## 💾 Phase 5 — Deploy Storage VM (iSCSI + NFS)

Run: `sudo bash scripts/04-deploy-storage.sh`

Creates an Ubuntu Server VM (4 GB RAM, 500 GB disk) for shared storage.

### Post-Install Storage Configuration

SSH into the Storage VM (192.168.100.30):

```bash
# ─── Set Static IP ───
cat > /etc/netplan/00-config.yaml << 'EOF'
network:
  version: 2
  ethernets:
    ens3:
      addresses: [192.168.100.30/24]
      routes:
        - to: default
          via: 192.168.100.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
    ens4:
      addresses: [10.0.1.30/24]
EOF
sudo netplan apply

# ─── Install Storage Services ───
sudo apt update && sudo apt install -y targetcli-fb nfs-kernel-server

# ─── Create iSCSI Target ───
sudo mkdir -p /storage
sudo truncate -s 300G /storage/iscsi-lun0.img

sudo targetcli <<EOCTL
/backstores/fileio create lun0 /storage/iscsi-lun0.img 300G
/iscsi create iqn.2026-03.lab.local:storage
/iscsi/iqn.2026-03.lab.local:storage/tpg1/acls create iqn.1998-01.com.vmware:esxi01
/iscsi/iqn.2026-03.lab.local:storage/tpg1/acls create iqn.1998-01.com.vmware:esxi02
/iscsi/iqn.2026-03.lab.local:storage/tpg1/luns create /backstores/fileio/lun0
/iscsi/iqn.2026-03.lab.local:storage/tpg1/portals create 10.0.1.30 3260
saveconfig
exit
EOCTL

sudo systemctl enable --now rtslib-fb-targetctl

# ─── Create NFS Share ───
sudo mkdir -p /storage/nfs-share
sudo chmod 777 /storage/nfs-share
echo "/storage/nfs-share 192.168.100.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
echo "/storage/nfs-share 10.0.1.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ra
sudo systemctl enable --now nfs-kernel-server
```

### Connect ESXi Hosts to Shared Storage

**iSCSI (from each ESXi host via SSH):**
```bash
esxcli iscsi software set --enabled=true
ADAPTER=$(esxcli iscsi adapter list | grep vmhba | awk '{print $1}')
esxcli iscsi adapter set -A $ADAPTER -n iqn.1998-01.com.vmware:esxi01   # esxi02 for Host 02
esxcli iscsi adapter discovery sendtarget add -A $ADAPTER -a 10.0.1.30:3260
esxcli iscsi adapter discovery rediscover -A $ADAPTER
esxcli storage core adapter rescan --adapter $ADAPTER
```

**NFS:**
```bash
esxcli storage nfs add -H 192.168.100.30 -s /storage/nfs-share -v nfs-shared
```

---

## 📊 Phase 6 — Deploy Monitoring VM (Grafana + Prometheus)

Run: `sudo bash scripts/06-deploy-monitoring.sh`

> If the VM reboots back into the Ubuntu installer, eject the ISO from the KVM host:
> `sudo virsh change-media monitoring-vm sda --eject --config && sudo virsh destroy monitoring-vm && sudo virsh start monitoring-vm`

### Post-Install Monitoring Setup

SSH into Monitor VM (192.168.100.40):

```bash
# ─── Static IP ───
sudo tee /etc/netplan/00-config.yaml > /dev/null << 'EOF'
network:
  version: 2
  ethernets:
    ens3:
      addresses: [192.168.100.40/24]
      routes:
        - to: default
          via: 192.168.100.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
EOF
sudo chmod 600 /etc/netplan/00-config.yaml
sudo netplan apply

# ─── Install Docker ───
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER

# ─── Prometheus Config ───
sudo mkdir -p /opt/monitoring/{prometheus,grafana}

sudo tee /opt/monitoring/prometheus/prometheus.yml > /dev/null << 'PROMEOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node-exporter'
    static_configs:
      - targets: ['192.168.100.40:9100']

  - job_name: 'storage-node'
    static_configs:
      - targets: ['192.168.100.30:9100']

  - job_name: 'proxmox-bs-node'
    static_configs:
      - targets: ['192.168.100.50:9100']
PROMEOF

# ─── Docker Compose ───
sudo tee /opt/monitoring/docker-compose.yml > /dev/null << 'DCEOF'
version: '3.8'
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=30d'

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false

  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'

volumes:
  prometheus_data:
  grafana_data:
DCEOF

cd /opt/monitoring && sudo docker compose up -d

# Optional: run node-exporter on Storage VM and Proxmox BS so targets above become UP
# (run on each target VM)
# sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter || true
# wget -qO- https://github.com/prometheus/node_exporter/releases/latest/download/node_exporter-1.8.2.linux-amd64.tar.gz \
#   | sudo tar -xz -C /usr/local/bin --strip-components=1 node_exporter-1.8.2.linux-amd64/node_exporter
# cat <<'UNIT' | sudo tee /etc/systemd/system/node_exporter.service > /dev/null
# [Unit]
# Description=Prometheus Node Exporter
# After=network-online.target
# [Service]
# User=node_exporter
# Group=node_exporter
# ExecStart=/usr/local/bin/node_exporter
# Restart=always
# [Install]
# WantedBy=multi-user.target
# UNIT
# sudo systemctl daemon-reload && sudo systemctl enable --now node_exporter
```

**Access:**
- Grafana: `http://192.168.100.40:3000` (admin / admin)
- Prometheus: `http://192.168.100.40:9090`

---

## 🛡️ Phase 7 — Deploy Proxmox Backup Server

Run: `sudo bash scripts/05-deploy-proxmox.sh`

> **Prerequisite**: Download Proxmox Backup Server ISO → `/var/lib/libvirt/images/proxmox-backup-server.iso`

### Post-Install Configuration

1. Access Web UI: `https://192.168.100.50:8007`
2. Login: `root` + password set during install
3. Set static IP during installation: `192.168.100.50/24`, gateway `192.168.100.1`, DNS `8.8.8.8`
4. Create a directory-backed datastore at `/mnt/backup-store`

---

## 🏢 Phase 8 — Deploy Windows Server (AD + DNS)

Run: `sudo bash scripts/07-deploy-winserver.sh`

> **Prerequisites**:
> - Download [Windows Server 2022 Evaluation](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022) → `/var/lib/libvirt/images/windows-server-2022.iso`
> - VirtIO drivers are downloaded automatically by the script

### Windows Installation

1. Connect via VNC: `virsh vncdisplay win-ad-dns`
2. Choose **Desktop Experience** (not Core)
3. When disk not found → **Load Driver** → browse virtio CD → `amd64\w2k22`
4. Set Administrator password

### Post-Install: Static IP

In Windows, set the network adapter:
```
IP:      192.168.100.60
Mask:    255.255.255.0
Gateway: 192.168.100.1
DNS:     127.0.0.1
```

### Post-Install: AD + DNS Setup (PowerShell as Admin)

```powershell
# 1. Install AD + DNS roles
Install-WindowsFeature -Name AD-Domain-Services,DNS -IncludeManagementTools

# 2. Promote to Domain Controller
Install-ADDSForest `
  -DomainName "lab.local" `
  -DomainNetbiosName "LAB" `
  -InstallDns:$true `
  -SafeModeAdministratorPassword (ConvertTo-SecureString "Hamida1998*/e1337" -AsPlainText -Force) `
  -Force:$true

# 3. After reboot, add DNS forwarder (for internet resolution)
Add-DnsServerForwarder -IPAddress 8.8.8.8

# 4. Add DNS records for all lab VMs
Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "pfsense"  -IPv4Address "192.168.100.2"
Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "esxi01"   -IPv4Address "192.168.100.10"
Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "esxi02"   -IPv4Address "192.168.100.11"
Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "vcenter01" -IPv4Address "192.168.100.20"
Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "storage"  -IPv4Address "192.168.100.30"
Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "monitor"  -IPv4Address "192.168.100.40"
Add-DnsServerResourceRecordA -ZoneName "lab.local" -Name "proxmox"  -IPv4Address "192.168.100.50"
```

> After AD is running, update **all lab VMs** to use DNS `192.168.100.60` instead of `8.8.8.8`.
> This lets them resolve `vcenter01.lab.local`, `esxi01.lab.local`, etc.

---

## 🔒 Phase 9 — Deploy pfSense Firewall

Run: `sudo bash scripts/08-deploy-pfsense.sh`

> **Prerequisite**: Download [pfSense CE ISO](https://www.pfsense.org/download/) → `/var/lib/libvirt/images/pfSense-CE-2.7.2-RELEASE-amd64.iso`

### pfSense Installation

1. Connect via VNC: `virsh vncdisplay pfsense`
2. Accept defaults, install to disk
3. After reboot, assign interfaces:
   - **WAN** = `vtnet0` (br0-mgmt)
   - **LAN** = `vtnet1` (br-lan)
4. Set WAN IP: `192.168.100.2/24`, gateway `192.168.100.1`
5. Set LAN IP: `10.10.0.1/24`

### Post-Install: Web UI Configuration

Access: `https://192.168.100.2` (admin / pfsense)

**Configure VLANs** (Interfaces → VLANs → Add):

| VLAN ID | Name | Subnet | Purpose |
|---|---|---|---|
| 10 | Management | 192.168.10.0/24 | ESXi/vCenter mgmt |
| 20 | Servers | 192.168.20.0/24 | Production VMs |
| 30 | Storage | 192.168.30.0/24 | iSCSI/NFS traffic |
| 40 | DMZ | 192.168.40.0/24 | Public-facing services |

**Firewall Rules** (Firewall → Rules):
- Allow Management → all VLANs
- Allow Servers → Storage (iSCSI/NFS)
- Block Servers → Management
- Allow DMZ → Internet only

---

## ✅ Phase 10 — Post-Deployment Verification

### Connectivity Matrix

```bash
# Run from KVM host
for ip in 2 10 11 20 30 40 50 60; do
  echo -n "192.168.100.$ip: "
  ping -c1 -W2 192.168.100.$ip > /dev/null 2>&1 && echo "✅ UP" || echo "❌ DOWN"
done
```

### Service Verification

| Service | URL | Expected |
|---|---|---|
| pfSense | `https://192.168.100.2` | Firewall WebGUI |
| ESXi Host 01 | `https://192.168.100.10` | ESXi Web UI |
| ESXi Host 02 | `https://192.168.100.11` | ESXi Web UI |
| vCenter Server | `https://192.168.100.20` | vSphere Client |
| Grafana | `http://192.168.100.40:3000` | Dashboard |
| Prometheus | `http://192.168.100.40:9090` | Query UI |
| Proxmox BS | `https://192.168.100.50:8007` | Backup Console |
| Windows AD | RDP `192.168.100.60:3389` | AD Domain Controller |

### vSphere Cluster Checks
```
✓ Datacenter "MiniDC-Lab" created
✓ Cluster "HA-Cluster" with HA + DRS enabled
✓ Both ESXi hosts added and connected
✓ vMotion network configured (vmk1, 10.0.0.x)
✓ Shared iSCSI datastore visible on both hosts
✓ NFS datastore mounted on both hosts
✓ Test VM migration (vMotion) succeeds
```

---

## 📁 File Structure

```
vm/
├── README.md                          ← This guide
├── scripts/
│   ├── 00-cleanup.sh                  ← Full wipe (VMs + networks + disks)
│   ├── 01-network-setup.sh            ← Bridge networks (mgmt, vMotion, iSCSI)
│   ├── 02-deploy-esxi.sh              ← ESXi Host 01 & 02 (on KVM)
│   ├── 03-deploy-vcsa-kvm.sh          ← vCenter Server (DIRECT on KVM)
│   ├── 04-deploy-storage.sh           ← Storage VM (Ubuntu)
│   ├── 05-deploy-proxmox.sh           ← Proxmox Backup Server
│   ├── 06-deploy-monitoring.sh        ← Monitoring VM (Ubuntu)
│   ├── 07-deploy-winserver.sh         ← Windows Server AD + DNS
│   ├── 08-deploy-pfsense.sh           ← pfSense Firewall / Router
│   └── deploy-all.sh                  ← Master deployment script
└── configs/
    ├── vcsa-deploy.json               ← vCenter CLI installer template
    └── esxi-ks.cfg                    ← ESXi kickstart (optional)
```

---

## ⚠️ Important Notes

1. **Nested Virtualization** must be enabled on the KVM host (`kvm_intel nested=1`)
2. **vCenter on KVM** — deployed directly as QCOW2 VM, NOT inside ESXi. This avoids nested virt lockups.
3. **ESXi ISOs** are not redistributable — download from [Broadcom Support](https://support.broadcom.com/)
4. **vCenter "small" deployment** requires ~24 GB RAM + ~600 GB disk (thin provisioned uses much less initially)
5. **Passwords** — change all placeholder passwords before deployment!
6. **vMotion** requires shared storage — complete Phase 5 before testing live migration
7. **Firewall** — ensure `iptables` NAT is persistent across reboots (handled by libvirt)
