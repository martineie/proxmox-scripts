#!/usr/bin/env bash

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

# Download the image
wget $IMAGE_URL -O /tmp/$IMAGE_NAME

# Delete existing VM if it exists
qm destroy $VM_ID

# Create new VM
qm create $VM_ID --name $VM_NAME --net0 virtio,bridge=$BRIDGE --scsihw $SCSI_CONTROLLER --machine $MACHINE --bios $BIOS --cpu $CPU_TYPE --cores $CORES --memory $MEMORY

# Import operating system disk
qm importdisk $VM_ID /tmp/$IMAGE_NAME $STORAGE_NAME


virt-customize -a /tmp/$IMAGE_NAME --install qemu-guest-agent

# Configure VM hardware
qm set $VM_ID -efidisk0 ${DISK0_REF}${FORMAT} -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} -scsi1 ${STORAGE}:cloudinit -boot order=scsi0 -serial0 socket >/dev/null

# Resize disk
qm resize $VM_ID scsi0 ${DISK_SIZE} >/dev/null

# Remove cd/dvd drive
if qm config $VM_ID | grep -q '^ide2:'; then
  qm set $VM_ID --delete ide2
fi

# Create cloud-init drive
qm set $VM_ID --ide2 $STORAGE:cloudinit


#qm template $VM_ID

m create $VM_ID -agent 1${MACHINE} -tablet 0 -localtime 1 -bios ovmf${CPU_TYPE} -cores $CORE_COUNT -memory $MEMORY \
  -name $HN -tags community-script -net0 virtio,bridge=$BRG,macaddr=$MAC$VLAN$MTU -onboot 1 -ostype l26 -scsihw virtio-scsi-pci

# Create empty disk for EFI
pvesm alloc $STORAGE $VM_ID $DISK0 4M 1>&/dev/null

# 
qm importdisk $VM_ID ${FILE} $STORAGE ${DISK_IMPORT:-} 1>&/dev/null
if [ "$CLOUD_INIT" == "yes" ]; then
  qm set $VM_ID \
    -efidisk0 ${DISK0_REF}${FORMAT} \
    -scsi0 ${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE} \
    -scsi1 ${STORAGE}:cloudinit \
    -boot order=scsi0 \
    -serial0 socket >/dev/null

