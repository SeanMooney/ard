# Static DevStack AIO with Cyborg and pci-sim

This example deploys an all-in-one DevStack workload to a pre-provisioned
CentOS Stream 10 host through the ARD static provider. It enables the Cyborg
DevStack plugin and its pci-sim integration, which builds and loads the
`fake_pci_sriov` kernel module.

## Prerequisites

The target host must:

- run CentOS Stream 10;
- have a `stack` user with passwordless sudo;
- be reachable through an OpenSSH host alias; and
- provide KVM and IOMMU support, or permit unsafe VFIO interrupts.

The example expects an SSH alias named `dev-host`:

```sshconfig
Host dev-host
  HostName host.example.com
  User stack
  IdentityFile ~/.ssh/id_ed25519_stack
```

Change `ansible_host` in `render.yaml` if a different alias is used. The
logical Ansible node name and rendered hostname remain `aio`; the SSH alias is
transport configuration and is not used as the workload address.

## Render intent

The Cyborg plugin is passed through `controller_devstack_plugins`. pci-sim
settings are passed through `controller_localrc_extra`:

```yaml
ard_render_overrides:
  devstack:
    controller:
      controller_devstack_plugins:
        cyborg: https://opendev.org/openstack/cyborg
      controller_localrc_extra:
        ENABLE_PCI_SIM: true
        PCI_SIM_NUM_PFS: 2
        PCI_SIM_NUM_VFS: 4
        PCI_SIM_ALLOW_UNSAFE_INTERRUPTS: true
```

The AIO host belongs to the `controller` and `switch` groups. It is not a
multinode `peer` or `subnode`, and the controller role runs the compute service
locally.

## Deploy with Make

Choose a deployment name and render this example:

```bash
make render \
  ARD_DEPLOYMENT=static-cyborg-pci-sim \
  ARD_RENDER_FILE=examples/devstack/static-cyborg-pci-sim/render.yaml
```

Prepare the existing host, confirm connectivity, and deploy DevStack:

```bash
make apply ARD_DEPLOYMENT=static-cyborg-pci-sim
make ping ARD_DEPLOYMENT=static-cyborg-pci-sim
make deploy ARD_DEPLOYMENT=static-cyborg-pci-sim
```

During `apply`, the static provider connects through `ansible_host`, discovers
the host's default IPv4 and IPv6 addresses, and persists them in the generated
inventory for DevStack endpoint configuration.

## Validate

Open an SSH session through the generated inventory:

```bash
make ssh ARD_DEPLOYMENT=static-cyborg-pci-sim ARD_NODE=aio
```

On the target host, confirm the generated configuration:

```bash
grep -E '^(enable_plugin cyborg|ENABLE_PCI_SIM|PCI_SIM_)' \
  /opt/repos/devstack/local.conf
lsmod | grep fake_pci_sriov
systemctl --no-pager --type=service 'devstack@cyborg*'
```

Expected `local.conf` values include:

```text
enable_plugin cyborg https://opendev.org/openstack/cyborg
ENABLE_PCI_SIM="True"
PCI_SIM_NUM_PFS="2"
PCI_SIM_NUM_VFS="4"
PCI_SIM_ALLOW_UNSAFE_INTERRUPTS="True"
```

`PCI_SIM_ALLOW_UNSAFE_INTERRUPTS=True` relaxes VFIO isolation and is intended
only for disposable development systems.

## Redeploy

The static provider does not own the host lifecycle, and `make destroy` does
not unstack DevStack. Before rerunning a deployment that reached `stack.sh`, use
the Make SSH interface and unstack on the target:

```bash
make ssh ARD_DEPLOYMENT=static-cyborg-pci-sim ARD_NODE=aio
```

```bash
cd /opt/repos/devstack
./unstack.sh
exit
```

Then repeat `make render`, `make apply`, and `make deploy`.
