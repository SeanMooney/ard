# ard_multinode_known_hosts

Build and install a deterministic multinode `/etc/ssh/ssh_known_hosts` block
for ARD environments.

This role is an ARD-local replacement for the Zuul `multi-node-known-hosts`
role. The upstream role generates a large list from every interface address and
then updates `known_hosts` once per entry on every host. In KubeVirt and other
nested environments this includes many transient veth and link-local addresses,
which makes the work grow quickly and slows multinode setup.

`ard_multinode_known_hosts` keeps the same high-level goal while doing less
work:

- generate the canonical entry list once with `run_once`;
- use only stable inventory/provider aliases and addresses;
- update each host once with a managed block;
- preserve unrelated content in `/etc/ssh/ssh_known_hosts`.

The implementation intentionally uses Ansible host key facts rather than
`ssh-keyscan`. That avoids scan timeouts and keeps generation deterministic.

## Variables

| Variable | Default | Description |
| --- | --- | --- |
| `ard_multinode_known_hosts_group` | `all` | Inventory group to include in the generated block. |
| `ard_multinode_known_hosts_path` | `/etc/ssh/ssh_known_hosts` | System known hosts file to update. |
| `ard_multinode_known_hosts_include_datacenter` | `true` | Include `nodepool.datacenter_ipv4` aliases when present. |
| `ard_multinode_known_hosts_include_bridge` | `true` | Include `nodepool.bridge_ipv4` aliases when present. |

## Included aliases

For each host, the role includes stable names and addresses when available:

- `inventory_hostname`
- `ansible_hostname`
- `ansible_host`
- `ard_provider_resource_name`
- `nodepool.interface_ip`
- `nodepool.public_ipv4`
- `nodepool.private_ipv4`
- `nodepool.public_ipv6`
- `nodepool.datacenter_ipv4`
- `nodepool.bridge_ipv4`

Link-local IPv6 and loopback aliases are skipped.
