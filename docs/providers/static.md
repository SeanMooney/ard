# Static provider

The ARD static provider targets pre-provisioned hosts over SSH. It generates the
same deployment workspace and workload inventory used by managed providers, but
it does not create, reboot, or delete the host.

## Host prerequisites

Each target must have:

- an SSH account accepted by Ansible;
- passwordless sudo when `ansible_become: true` is selected;
- Python 3; and
- the CPU, memory, storage, virtualization, and networking capabilities needed
  by the selected workload.

An OpenSSH alias can be used as `ansible_host`:

```sshconfig
Host dev-host
  HostName host.example.com
  User stack
  IdentityFile ~/.ssh/id_ed25519_stack
```

The SSH alias is only the transport address. Give the inventory node a logical
name such as `aio`, `controller`, or `compute-1`.

## Static node declaration

A single-node DevStack host can be declared in render intent:

```yaml
ard_provider: static
ard_provider_profile: local-static
ard_topology: all-in-one
ard_static_nodes:
  - name: aio
    hostname: aio
    ansible_host: dev-host
    ansible_user: stack
    ansible_private_key_file: ""
    ansible_ssh_common_args: ""
    ansible_become: true
    groups:
      - controller
      - switch
```

Empty private-key and common-argument values allow OpenSSH configuration to
control authentication and connection policy. Alternatively, set explicit
Ansible SSH values in the node declaration.

A DevStack AIO node is a controller and bridge switch, but not a multinode
`peer` or `subnode`. Multinode-only host, firewall, bridge, and key-copy setup is
skipped when the inventory has no peers.

## Lifecycle

Render an example into a named deployment workspace:

```bash
make render \
  ARD_DEPLOYMENT=static-aio \
  ARD_RENDER_FILE=examples/devstack/static-cyborg-pci-sim/render.yaml
```

Then run each lifecycle stage explicitly:

```bash
make apply ARD_DEPLOYMENT=static-aio
make ping ARD_DEPLOYMENT=static-aio
make deploy ARD_DEPLOYMENT=static-aio
make verify ARD_DEPLOYMENT=static-aio
```

For static deployments, `apply` validates the declaration, waits for SSH and
cloud-init, installs ARD base packages, gathers network facts, and regenerates
the inventory with discovered workload addresses. For example:

```yaml
all:
  hosts:
    aio:
      ansible_host: dev-host
      nodepool:
        private_ipv4: 192.0.2.10
        public_ipv4: 192.0.2.10
```

`ansible_host` remains the SSH alias, while `nodepool.private_ipv4` supplies the
real address required by DevStack `HOST_IP` and service endpoints.

`make destroy` is an infrastructure no-op for this provider. It does not remove
packages or run DevStack's `unstack.sh` on an existing host.

## DevStack overrides and plugins

Render-time DevStack configuration belongs under
`ard_render_overrides.devstack`:

```yaml
ard_render_overrides:
  devstack:
    controller:
      controller_devstack_plugins:
        cyborg: https://opendev.org/openstack/cyborg
      controller_localrc_extra:
        ENABLE_PCI_SIM: true
```

The controller role passes `controller_devstack_plugins` and
`controller_localrc_extra` to DevStack's `write-devstack-local-conf` role.
Multinode deployments can similarly use `compute_devstack_plugins` and compute
local configuration overrides.

Use deployment-local `local-vars.yaml` for site-specific values that should not
be part of reusable render intent, such as proxy URLs or credentials.

## Reusing a host

If `stack.sh` began installing services, unstack before redeploying. Open the
host through Make:

```bash
make ssh ARD_DEPLOYMENT=static-aio ARD_NODE=aio
```

Then run on the host:

```bash
cd /opt/repos/devstack
./unstack.sh
exit
```

Repeat `make render`, `make apply`, and `make deploy` after cleanup.

See
[the static Cyborg and pci-sim example](../../examples/devstack/static-cyborg-pci-sim/)
for a complete CentOS Stream 10 deployment.
