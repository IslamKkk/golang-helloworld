#cloud-config
package_update: true
packages:
  - curl

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
hostname: k3s-${node_role}
manage_etc_hosts: true

runcmd:
  - |
    if [ "${node_role}" = "server" ]; then
      curl -sfL https://get.k3s.io | K3S_TOKEN="${k3s_token}" INSTALL_K3S_VERSION="v1.34.1+k3s1" INSTALL_K3S_EXEC="server --disable=traefik --node-ip=${node_ip} --advertise-address=${node_ip}" sh -
    else
      until curl --silent --fail --connect-timeout 2 "https://${server_ip}:6443/cacerts" >/dev/null; do sleep 10; done
      curl -sfL https://get.k3s.io | K3S_TOKEN="${k3s_token}" K3S_URL="https://${server_ip}:6443" INSTALL_K3S_VERSION="v1.34.1+k3s1" INSTALL_K3S_EXEC="agent --node-ip=${node_ip}" sh -
    fi
