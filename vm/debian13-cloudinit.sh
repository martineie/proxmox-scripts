#!/usr/bin/env bash
set -euo pipefail

# ------------------------------
# Configuration (overridable)
# ------------------------------
# Core VM/image settings
IMAGE_URL="${IMAGE_URL:-https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2}"
IMAGE_NAME="${IMAGE_NAME:-$(basename "$IMAGE_URL")}"
VM_ID="${VM_ID:-9000}"
VM_NAME="${VM_NAME:-debian13-cloudinit}"
STORAGE_NAME="${STORAGE_NAME:-local-lvm}"
AGENT_ENABLE="${AGENT_ENABLE:-1}"

# Hardware settings
MEMORY="${MEMORY:-1024}"
CORES="${CORES:-1}"
CPU_TYPE="${CPU_TYPE:-host}"
BIOS="${BIOS:-ovmf}"
MACHINE="${MACHINE:-q35}"
SCSI_CONTROLLER="${SCSI_CONTROLLER:-virtio-scsi-single}"
DISK_SIZE="${DISK_SIZE:-8G}"
DISK_CACHE="${DISK_CACHE:-}"

# Network settings
BRIDGE="${BRIDGE:-vmbr0}"
VLAN="${VLAN:-}"
MTU="${MTU:-}"

# Cloud-init settings
SNIPPETS_DIR="${SNIPPETS_DIR:-/var/lib/vz/snippets}"
CI_USERNAME="${CI_USERNAME:-martin}"
CI_PASSWORD="${CI_PASSWORD:-}"
CI_SSH_KEY="${CI_SSH_KEY:-}"
VM_HOSTNAME="${VM_HOSTNAME:-debian}"
CI_PACKAGE_UPDATE="${CI_PACKAGE_UPDATE:-false}"
CI_PACKAGE_UPGRADE="${CI_PACKAGE_UPGRADE:-false}"
CI_PACKAGES="${CI_PACKAGES:-qemu-guest-agent}"

NETWORK_MODE="${NETWORK_MODE:-dhcp}"      # dhcp | static
IPV4_CIDR="${IPV4_CIDR:-}"
IPV4_GW="${IPV4_GW:-}"

# Execution helpers
DRY_RUN="${DRY_RUN:-false}"
FORCE_RECREATE="${FORCE_RECREATE:-false}"

# Storage tuning defaults
THIN="${THIN:-discard=on,ssd=1,}"
FORMAT=",efitype=4m"

# ------------------------------
# Input validation
# ------------------------------
if [[ $# -gt 0 ]]; then
  echo "This script uses environment variables only."
  echo "Set variables inline, for example:"
  echo "VM_ID=9010 VM_NAME=debian-test DRY_RUN=true ./vm/debian13-cloudinit.sh"
  exit 1
fi

# ------------------------------
# Helper functions
# ------------------------------
run_cmd() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

# Validate static network inputs early.
if [[ "$NETWORK_MODE" == "static" ]]; then
  if [[ -z "$IPV4_CIDR" || -z "$IPV4_GW" ]]; then
    echo "When --network-mode static is set, --ip4-cidr and --ip4-gw are required."
    exit 1
  fi
fi

# ------------------------------
# Workspace setup and image fetch
# ------------------------------
TEMP_DIR="$(mktemp -d)"
cleanup() {
  popd >/dev/null || true
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$SNIPPETS_DIR"
pushd "$TEMP_DIR" >/dev/null
wget "$IMAGE_URL" -O "$IMAGE_NAME"

# ------------------------------
# Cloud-init user-data rendering
# ------------------------------
USER_DATA_FILE="$SNIPPETS_DIR/user-data-$VM_ID.yaml"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "[dry-run] would generate cloud-init user-data at $USER_DATA_FILE"
else
  # Build cloud-init user-data from environment-configured values.
  cat > "$USER_DATA_FILE" <<EOF
#cloud-config
hostname: $VM_HOSTNAME
users:
  - name: $CI_USERNAME
    groups: sudo
    shell: /bin/bash
EOF

  if [[ -n "$CI_PASSWORD" ]]; then
    cat >> "$USER_DATA_FILE" <<EOF
    passwd: $CI_PASSWORD
EOF
  fi

  if [[ -n "$CI_SSH_KEY" ]]; then
    cat >> "$USER_DATA_FILE" <<EOF
    ssh_authorized_keys:
      - $CI_SSH_KEY
EOF
  fi

  {
    echo "packages:"
    IFS=',' read -r -a pkgs <<< "$CI_PACKAGES"
    for pkg in "${pkgs[@]}"; do
      echo "  - ${pkg// /}"
    done
    echo "package_update: $CI_PACKAGE_UPDATE"
    echo "package_upgrade: $CI_PACKAGE_UPGRADE"
    echo "runcmd:"
    echo "  - systemctl enable qemu-guest-agent"
    echo "  - systemctl start qemu-guest-agent"
  } >> "$USER_DATA_FILE"
fi

# ------------------------------
# Storage backend mapping
# ------------------------------
STORAGE_TYPE="$(pvesm status -storage "$STORAGE_NAME" | awk 'NR>1 {print $2}')"
case "$STORAGE_TYPE" in
  nfs|dir)
    DISK_EXT=".qcow2"
    DISK_REF="$VM_ID/"
    DISK_IMPORT="-format qcow2"
    THIN=""
    ;;
  btrfs)
    DISK_EXT=".raw"
    DISK_REF="$VM_ID/"
    DISK_IMPORT="-format raw"
    THIN=""
    ;;
  lvmthin|zfspool)
    DISK_EXT=""
    DISK_REF=""
    DISK_IMPORT=""
    ;;
  *)
    DISK_EXT=""
    DISK_REF=""
    DISK_IMPORT=""
    ;;
esac

# Build deterministic disk references used by qm set.
for i in 0 1; do
  disk="DISK$i"
  eval "DISK${i}=vm-${VM_ID}-disk-${i}${DISK_EXT:-}"
  eval "DISK${i}_REF=${STORAGE_NAME}:${DISK_REF:-}${!disk}"
done

# ------------------------------
# VM create and disk attach flow
# ------------------------------
# Only destroy an existing VM when explicitly requested.
if qm status "$VM_ID" >/dev/null 2>&1; then
  if [[ "$FORCE_RECREATE" == "true" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[dry-run] qm destroy $VM_ID --destroy-unreferenced-disks 1 --purge 1"
    else
      qm destroy "$VM_ID" --destroy-unreferenced-disks 1 --purge 1 >/dev/null
    fi
  else
    echo "VM $VM_ID already exists. Set FORCE_RECREATE=true to destroy and recreate it."
    exit 1
  fi
fi

NET0="virtio,bridge=$BRIDGE"
[[ -n "$VLAN" ]] && NET0="$NET0,tag=$VLAN"
[[ -n "$MTU" ]] && NET0="$NET0,mtu=$MTU"

run_cmd qm create "$VM_ID" \
  --name "$VM_NAME" \
  --machine "$MACHINE" \
  --bios "$BIOS" \
  --cpu "$CPU_TYPE" \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --net0 "$NET0" \
  --scsihw "$SCSI_CONTROLLER" \
  --agent "enabled=$AGENT_ENABLE" \
  --vga serial0 \
  --serial0 socket

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[dry-run] pvesm alloc $STORAGE_NAME $VM_ID $DISK0 4M >/dev/null"
else
  pvesm alloc "$STORAGE_NAME" "$VM_ID" "$DISK0" 4M >/dev/null
fi
run_cmd qm importdisk "$VM_ID" "$IMAGE_NAME" "$STORAGE_NAME" ${DISK_IMPORT:-}

run_cmd qm set "$VM_ID" \
  --efidisk0 "${DISK0_REF}${FORMAT}" \
  --scsi0 "${DISK1_REF},${DISK_CACHE}${THIN}size=${DISK_SIZE}" \
  --scsi1 "${STORAGE_NAME}:cloudinit" \
  --boot "order=scsi0"

run_cmd qm resize "$VM_ID" scsi0 "$DISK_SIZE"

# ------------------------------
# Cloud-init and networking
# ------------------------------
if [[ "$NETWORK_MODE" == "dhcp" ]]; then
  run_cmd qm set "$VM_ID" --ipconfig0 ip=dhcp
else
  run_cmd qm set "$VM_ID" --ipconfig0 "ip=${IPV4_CIDR},gw=${IPV4_GW}"
fi
run_cmd qm set "$VM_ID" --cicustom "user=local:snippets/user-data-$VM_ID.yaml"

run_cmd qm cloudinit update "$VM_ID"

# ------------------------------
# Result
# ------------------------------
echo "VM $VM_ID created successfully."
echo "Cloud-init user-data: $USER_DATA_FILE"