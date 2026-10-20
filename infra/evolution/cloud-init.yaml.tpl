#cloud-config
package_update: true
packages:
  - docker.io
  - docker-compose-v2

users:
  - name: ubuntu
    ssh-authorized-keys:
      - ${ssh_public_key}
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true

ssh_pwauth: false
disable_root: true
hostname: ${vm_name}
manage_etc_hosts: true

runcmd:
  - [systemctl, enable, --now, docker]
  - [usermod, -aG, docker, ubuntu]
