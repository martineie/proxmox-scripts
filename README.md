# Proxmox VM Creation Scripts

This repository contains scripts to automate the creation of virtual machines in Proxmox VE using cloud-init.

## Scripts

- `debian13-cloudinit.sh`: Creates a Debian 13 VM with cloud-init configuration.

## Usage

Run the script directly from the repository:

```bash
curl -fsSL https://raw.githubusercontent.com/martineie/proxmox-scripts/main/vm/debian13-cloudinit.sh | bash
```

The script will read the necessary configuration from the GitHub repository and create the VM.

## Cloud-Init Configuration

The script uses the `user-data.yaml` file from this repository for cloud-init configuration. This file includes:

- User creation with sudo privileges
- SSH key setup
- Package installation (qemu-guest-agent)
- System updates and upgrades
- Service configuration

The script copies over the user-data.yaml configuration to set up the VM automatically upon first boot.

## Customization

- Edit the variables in the script to customize VM parameters (VM ID, memory, CPU cores, disk size, etc.).
- Modify `user-data.yaml` to change the cloud-init configuration (users, packages, SSH keys, etc.).

## Requirements

- Proxmox VE host
- Internet connection for downloading images
- Appropriate storage and network configuration in Proxmox

## Notes

Ensure that the VM ID and other parameters do not conflict with existing VMs on your Proxmox host.