#!/usr/bin/env bash

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
MAC="$GEN_MAC"
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

# Create a unique temporary directory
TEMP_DIR=$(mktemp -d)

# Change to the temp directory
pushd $TEMP_DIR >/dev/null

# Download the image
wget $IMAGE_URL -O $IMAGE_NAME

# Download user-data.yaml from GitHub
wget https://raw.githubusercontent.com/martineie/proxmox-scripts/main/vm/user-data.yaml -O user-data.yaml

# Delete existing VM if it exists
qm destroy $VM_ID

# Create new VM
qm create $VM_ID --name $VM_NAME --net0 virtio,bridge=$BRIDGE --scsihw $SCSI_CONTROLLER --machine $MACHINE --bios $BIOS --cpu $CPU_TYPE --cores $CORES --memory $MEMORY

# Import operating system disk
qm importdisk $VM_ID $IMAGE_NAME $STORAGE_NAME

# Configure VM hardware
qm set $VM_ID --efidisk0 $STORAGE_NAME:4 --scsi0 $STORAGE_NAME:0,size=$DISK_SIZE --ide2 $STORAGE_NAME:cloudinit --boot order=scsi0 --serial0 socket --agent enabled=$AGENT_ENABLE

# Create snippet directory if it doesn't exist
mkdir -p /var/lib/vz/snippets

# Copy user-data to snippets for cloud-init
cp user-data.yaml /var/lib/vz/snippets/user-data-$VM_ID.yaml

# Inject user-data via cloud-init custom configuration
qm set $VM_ID --cicustom user=$STORAGE_NAME:snippets/user-data-$VM_ID.yaml

echo "VM $VM_ID created successfully with cloud-init user-data configured."

# 
qm importdisk $VM_ID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
if [ "$CLOUD_INIT" == "yes" ]; then
  qm set $VM_ID \
    -efidisk0 ${DISK0_REF}${FORMAT} \
    -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
    -scsi1 ${STORAGE}:cloudinit \
    -boot order=scsi0 \
    -serial0 socket >/dev/null