#!/usr/bin/env bash
#set -euo pipefail

# Image and VM configuration
IMAGE_URL=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
IMAGE_NAME=$(basename $IMAGE_URL)
VM_ID="9000"
VM_NAME="debian13-cloudinit"
STORAGE_NAME="local-lvm"
AGENT_ENABLE="1"

# Hardware configuration
MEMORY="1024"
CORES="1"
CPU_TYPE="host"
BIOS="ovmf"
DISPLAY="default"
MACHINE="q35"
SCSI_CONTROLLER="virtio-scsi-single"
DISK_SIZE="8G"
DISK_CACHE=""
HOSTNAME="debian"

# Network configuration
BRIDGE="vmbr0"
#MAC="$GEN_MAC"
VLAN=""
MTU=""
METHOD="default"

# Define cleanup function to remove temp dir on exit
function cleanup() {
  popd >/dev/null
  rm -rf $TEMP_DIR
}

# Set trap to run cleanup on script exit
trap cleanup EXIT

# Create a unique temporary directory for downloads
TEMP_DIR=$(mktemp -d)

# Change to the temp directory
pushd $TEMP_DIR >/dev/null

# Download the image
wget $IMAGE_URL -O $IMAGE_NAME

# Download user-data.yaml to snippets directory
SNIPPETS_DIR="/var/lib/vz/snippets"
mkdir -p $SNIPPETS_DIR  # Ensure directory exists
wget https://raw.githubusercontent.com/martineie/proxmox-scripts/main/vm/user-data.yaml -O $SNIPPETS_DIR/user-data-$VM_ID.yaml

# Delete existing VM if it exists
qm destroy $VM_ID

# Create new VM
qm create $VM_ID \
  --name $VM_NAME \
  --machine $MACHINE \
  --bios $BIOS \
  --cpu $CPU_TYPE \
  --cores $CORES \
  --memory $MEMORY \
  --net0 virtio,bridge=$BRIDGE \
  --scsihw $SCSI_CONTROLLER \
  --agent enabled=$AGENT_ENABLE \
  --vga serial0 \
  --serial0 socket

# Import operating system disk
qm importdisk $VM_ID $IMAGE_NAME $STORAGE_NAME

# Configure disks
qm set $VM_ID --efidisk0 $STORAGE_NAME:4
qm set $VM_ID --scsi0 $STORAGE_NAME:1
qm set $VM_ID --ide0 $STORAGE_NAME:cloudinit

# Resize the disk to the desired size
qm resize $VM_ID scsi0 $DISK_SIZE

# Set boot order to ensure the VM boots from the disk
qm set $VM_ID --boot order=scsi0

# Configure cloud-init to use the custom user-data
qm set $VM_ID --cicustom "user=local:snippets/user-data-$VM_ID.yaml"

# Regenerate cloud-init ISO with custom data
# qm cloudinit update $VM_ID

# Configure network to use DHCP
qm set $VM_ID --ipconfig0 ip=dhcp

echo "VM $VM_ID created successfully with cloud-init user-data configured."