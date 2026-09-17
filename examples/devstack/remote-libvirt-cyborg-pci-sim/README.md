# Remote-libvirt DevStack AIO with Cyborg and pci-sim

This example deploys the same Cyborg and pci-sim workload as the static
provider example, but creates a CentOS Stream 10 all-in-one VM through a remote
libvirt execution host. The `devstack-control` flavor supplies 8 vCPUs, 16 GiB
of RAM, and an 80 GiB root disk.

Only provider bootstrap differs from the static example. Cloud-init creates the
minimal SSH user and network configuration needed for Ansible; shared apply and
workload roles perform all subsequent host preparation and DevStack deployment.

## Prerequisites

The execution host must:

- be reachable through an OpenSSH host alias;
- provide passwordless privilege escalation for the remote account;
- provide KVM with nested virtualization enabled;
- have at least 8 available CPUs, 16 GiB RAM, and 80 GiB storage; and
- satisfy the packages and services checked by the libvirt preflight role.

The optional bootstrap playbook installs and enables the host prerequisites:

```bash
uv run ansible-playbook \
  -i virt-host, \
  ansible/playbooks/provider/bootstrap-libvirt-host.yaml \
  -e ard_libvirt_bootstrap_user=stack
```

## Render and configure the execution host

Choose a deployment name and a management CIDR that does not overlap networks
on the execution host:

```bash
make render \
  ARD_DEPLOYMENT=remote-libvirt-cyborg-pci-sim \
  ARD_RENDER_FILE=examples/devstack/remote-libvirt-cyborg-pci-sim/render.yaml \
  ARD_NETWORK_CIDR=192.168.118.0/24
```

Create deployment-local `local-vars.yaml`; do not add site-specific SSH details
to the reusable render intent:

```yaml
---
ard_libvirt_execution_host:
  name: virt-host
  ansible_become: true
ard_libvirt_execution_image_dir: /var/lib/libvirt/images/ard
ard_libvirt_execution_image_cache_dir: /var/lib/libvirt/images/ard/cache
```

ARD records the non-secret execution endpoint and resolved remote paths in
`provider-state.yaml`. It keeps rendered state and inventory locally while VM
disks, seed media, console logs, and libvirt operations remain on the execution
host.

## Deploy

```bash
make apply ARD_DEPLOYMENT=remote-libvirt-cyborg-pci-sim
make ping ARD_DEPLOYMENT=remote-libvirt-cyborg-pci-sim
make deploy ARD_DEPLOYMENT=remote-libvirt-cyborg-pci-sim
```

The generated inventory proxies guest SSH through the execution host, so the
same inventory is used by apply, deploy, verify, and `make ssh`.

## Validate

Open an SSH session through the generated inventory:

```bash
make ssh ARD_DEPLOYMENT=remote-libvirt-cyborg-pci-sim ARD_NODE=controller
```

On the guest, verify the generated configuration, pci-sim module, and Cyborg
services:

```bash
grep -E '^(enable_plugin cyborg|ENABLE_PCI_SIM|PCI_SIM_)' \
  /opt/repos/devstack/local.conf
lsmod | grep fake_pci_sriov
systemctl list-units --all --type=service | grep cyborg
source /opt/repos/devstack/openrc admin admin
openstack endpoint list --service cyborg
openstack accelerator device list
```

Expected `local.conf` values match the static example:

```text
enable_plugin cyborg https://opendev.org/openstack/cyborg
ENABLE_PCI_SIM="True"
PCI_SIM_NUM_PFS="2"
PCI_SIM_NUM_VFS="4"
PCI_SIM_ALLOW_UNSAFE_INTERRUPTS="True"
```

`PCI_SIM_ALLOW_UNSAFE_INTERRUPTS=True` is suitable only for disposable
development systems.

## Validation status

This example was exercised against a CentOS Stream 10 execution host. Host
bootstrap, provider apply, proxied SSH, DevStack `stack.sh`, `make verify`,
OpenStack API checks, Cyborg services, and pci-sim device discovery succeeded.
The initial workload run exposed execution-host inventory leakage and an
unnecessary AIO certificate-sync step; after fixing both, the corrected
post-deploy flow passed with `run_devstack=false` without rerunning `stack.sh`.
Tempest and remote-libvirt multinode rsync were not validated.

## Access and cleanup

Print the exact proxied SSH command without connecting:

```bash
make ssh-print \
  ARD_DEPLOYMENT=remote-libvirt-cyborg-pci-sim \
  ARD_NODE=controller
```

Use `/opt/repos/devstack/openrc` and `local.conf` on the guest as the
authoritative sources for DevStack authentication settings. To inspect Horizon when the management network is
reachable only from the execution host, start a SOCKS proxy:

```bash
ssh -N -D 127.0.0.1:1080 virt-host
```

Configure the browser to use the SOCKS5 proxy at `127.0.0.1:1080` with remote
DNS resolution, then open `https://192.168.118.2/dashboard/`. Replace the
example address with the node's `ansible_host` from the generated inventory.
Keep site-specific SSH
details and populated deployment state out of the reusable example.

When finished, destroy the owned domain, networks, and remote runtime files:

```bash
make destroy-clean-generated ARD_DEPLOYMENT=remote-libvirt-cyborg-pci-sim
```
