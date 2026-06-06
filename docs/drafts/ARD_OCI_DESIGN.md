# ARD OCI Support Design Plan

## 1. Purpose

This document proposes an `ard-oci` provider layer for the ARD repository. The goal is to replace the current Vagrant/libvirt provisioning layer with OCI-backed system containers while preserving the existing DevStack deployment logic.

The initial supported container runtimes are Docker and Podman. The design keeps the provider contract backend-neutral so that systemd-nspawn can be added later, using modern systemd OCI support where available.

## 2. Assumptions

- Implementation happens in the ARD repository.
- Existing ARD DevStack playbooks and roles remain the deployment layer:
  - `ansible/deploy_multinode_devstack.yaml`
  - `ansible/devstack_common.yaml`
  - `ansible/roles/devstack_common/`
  - `ansible/roles/devstack_controller/`
  - `ansible/roles/devstack_compute/`
- Make targets and Molecule scenarios both call the same Ansible roles and playbooks.
- Molecule, if used, should use ansible-native or delegated create/destroy playbooks rather than owning a separate provisioning model.
- Zuul jobs should be able to call the same Ansible roles to create containerized DevStack nodes on a VM or bare-metal host.
- The default connection model is SSH into each container, not Docker/Podman exec, to preserve the VM-like assumptions already present in ARD and DevStack Zuul roles.
- Initial runtime mode is rootful. Rootless containers are out of scope for the first implementation because KVM, OVS, loop devices, LVM, and device mapper require host-level privileges.

## 3. Goals

1. Provide a reusable OCI image for DevStack-capable system-container nodes.
2. Provision controller and compute containers with stable names, hostnames, IPs, and Ansible groups.
3. Make container nodes look like the existing ARD and Zuul multinode inventory contract:
   - `controller`
   - `compute`
   - `subnode`
   - `peers`
   - `switch`
4. Reuse existing ARD DevStack roles with minimal changes.
5. Support local developer workflows through Make.
6. Support Molecule ansible-native workflows using the same create/deploy/verify/destroy playbooks.
7. Support Zuul jobs where Ansible provisions containers and then deploys DevStack inside them.
8. Keep Docker and Podman provider implementations behind the same node specification.
9. Keep a future path for systemd-nspawn.

## 4. Non-goals

- Do not split OpenStack services into one container per service.
- Do not replace DevStack with Kolla, Kolla-Ansible, or OpenStack-Helm.
- Do not provide production-grade isolation or hard multi-tenant security.
- Do not support rootless runtimes initially.
- Do not bake one fixed DevStack branch or commit into the normal node image.
- Do not make Molecule the authoritative provisioning mechanism.

## 5. High-level Architecture

```text
make / molecule / zuul
        |
        v
ard-oci provider playbooks
        |
        v
ard-oci provider roles
        |
        v
Docker / Podman / future nspawn backend
        |
        v
dynamic Ansible inventory
        |
        v
existing ARD DevStack deployment roles
        |
        v
stack.sh inside VM-like system containers
```

The provider layer is responsible only for making hosts exist and adding them to inventory. DevStack installation and configuration should continue to be handled by the existing ARD and DevStack roles.

## 6. Proposed Repository Layout

```text
ARD_OCI_DESIGN.md
Makefile

images/
  ard-devstack-node/
    Containerfile
    README.md
    systemd/
    sshd/

ansible/
  playbooks/
    oci-create.yaml
    oci-deploy-devstack.yaml
    oci-verify.yaml
    oci-destroy.yaml
    oci-collect-logs.yaml
    oci-site.yaml

  roles/
    ard_oci_preflight/
    ard_oci_image/
    ard_oci_network/
    ard_oci_node/
    ard_oci_inventory/
    ard_oci_destroy/
    ard_oci_collect_logs/

molecule/
  oci-multinode/
    molecule.yml
    create.yml
    converge.yml
    verify.yml
    destroy.yml
```

The exact names can be adjusted, but the separation should remain:

- image build assets under `images/`
- provider playbooks under `ansible/playbooks/`
- provider roles under `ansible/roles/`
- Molecule only as a workflow/test frontend

## 7. Backend-neutral Node Specification

The central contract should be a backend-neutral variable structure. Docker, Podman, and future nspawn support should all consume the same node spec.

Example:

```yaml
ard_oci_provider: podman
ard_oci_lifecycle: transient

ard_oci_image: localhost/ard-devstack-node:latest

ard_oci_network:
  name: ard-devstack
  subnet: 172.28.0.0/24
  gateway: 172.28.0.1

ard_oci_nodes:
  - name: controller
    hostname: controller
    ip: 172.28.0.2
    image: "{{ ard_oci_image }}"
    groups:
      - controller
      - switch
    profiles:
      - systemd
      - ssh
      - kvm
      - ovn

  - name: compute1
    hostname: compute1
    ip: 172.28.0.3
    image: "{{ ard_oci_image }}"
    groups:
      - compute
      - peers
      - subnode
    profiles:
      - systemd
      - ssh
      - kvm
      - ovn

  - name: compute2
    hostname: compute2
    ip: 172.28.0.4
    image: "{{ ard_oci_image }}"
    groups:
      - compute
      - peers
      - subnode
    profiles:
      - systemd
      - ssh
      - kvm
      - ovn
```

Provider-specific roles translate this abstract spec into Docker, Podman, or nspawn operations.

## 8. Capability Profiles

Profiles describe host integration requirements. They allow a scenario to opt into risky features explicitly.

### 8.1 `systemd`

Required for containers that boot a full systemd userspace.

Expected runtime settings:

- run `/sbin/init` or equivalent as PID 1
- pass cgroup support into the container
- use a systemd-compatible stop signal

Docker/Podman examples:

```yaml
privileged: true
cgroupns_mode: host
stop_signal: SIGRTMIN+3
volumes:
  - /sys/fs/cgroup:/sys/fs/cgroup:rw
```

The exact cgroup settings may need runtime-specific tuning.

### 8.2 `ssh`

Required for the initial ARD workflow because Ansible should connect to containers as if they were VMs.

Expected image contents:

- `sshd`
- `python3`
- `sudo`
- a `stack` user or enough base system functionality for Ansible to create one

Expected provisioning behavior:

- inject an SSH public key
- start sshd
- wait for port 22

### 8.3 `kvm`

Required when Nova should use KVM.

Expected runtime settings:

```yaml
devices:
  - /dev/kvm:/dev/kvm
  - /dev/net/tun:/dev/net/tun
```

If `/dev/kvm` is not available, preflight should either fail or downgrade to QEMU based on scenario variables.

### 8.4 `ovn` / `ovs`

Required for Neutron OVN or OVS based jobs.

Expected runtime settings:

```yaml
privileged: true
volumes:
  - /lib/modules:/lib/modules:ro
```

Preflight should check that the host has the needed kernel modules available or already loaded.

### 8.5 `storage-loop`

Required for loopback-backed services such as Swift loop disks.

Expected runtime settings:

```yaml
devices:
  - /dev/loop-control:/dev/loop-control
device_cgroup_rules:
  - "b 7:* rwm"
```

### 8.6 `storage-lvm`

Required for Cinder LVM backends.

Expected runtime settings may include:

```yaml
privileged: true
devices:
  - /dev/mapper/control:/dev/mapper/control
device_cgroup_rules:
  - "b 7:* rwm"
  - "c 10:236 rwm"
```

This should be an explicit advanced profile because it can affect host device state.

### 8.7 `container-engine`

Required if DevStack plugins need Docker, Podman, CRI-O, or nested container engines.

Two possible modes:

1. Run a nested container engine inside the DevStack node.
2. Bind-mount the host runtime socket into the node.

This design should not choose a default initially. It should define a profile and document the tradeoff later.

## 9. Inventory Contract

The provider must add each container as an Ansible host matching the existing ARD and DevStack expectations.

For each node:

```yaml
inventory_hostname: controller
ansible_host: 172.28.0.2
ansible_user: stack
ansible_private_key_file: ~/.ssh/id_ed25519_stack
nodepool:
  private_ipv4: 172.28.0.2
  public_ipv4: 172.28.0.2
zuul:
  executor:
    log_root: /tmp/zuul_logs
    work_root: /tmp/work_root
```

Groups come from the node spec:

```yaml
groups:
  - controller
  - switch
```

This preserves the assumptions in:

- `ansible/roles/devstack_common/tasks/main.yml`
- `ansible/roles/devstack_controller/defaults/main.yml`
- `ansible/roles/devstack_compute/defaults/main.yml`
- DevStack's `write-devstack-local-conf` and `orchestrate-devstack` roles

## 10. Connection Model

### 10.1 Initial mode: SSH

Use SSH into containers for the first implementation.

Reasons:

- matches current Vagrant/libvirt behavior
- matches Zuul/nodepool-style behavior
- supports `synchronize`/rsync roles naturally
- preserves SSH key setup in `ensure_stack_user`
- makes container nodes behave like small VMs

### 10.2 Future mode: runtime exec

Docker/Podman exec connection can be explored later.

Potential advantages:

- no sshd needed
- faster local execution
- fewer moving parts

Potential disadvantages:

- deviates from Zuul/nodepool assumptions
- may require changes to roles using SSH or rsync
- less representative of the existing ARD deployment path

## 11. OCI Image Design

### 11.1 Normal image: `ard-devstack-node`

This should be a branch-agnostic system-container image.

Example contents:

- base OS, initially Ubuntu 24.04 or a configurable distro
- systemd
- sshd
- python3
- sudo
- git
- rsync
- iproute2
- iputils-ping
- ca-certificates
- curl or wget
- basic debugging tools
- optional Open vSwitch packages if useful

It should not normally include a pinned DevStack checkout. DevStack source should be managed by Ansible via existing variables:

```yaml
devstack_repo_url: https://opendev.org/openstack/devstack
devstack_branch: master
devstack_refspec:
repo_dir: /opt/repos
```

### 11.2 Optional prewarmed image

A later optimization may add a prewarmed image:

```text
ard-devstack-node-prewarmed
```

Possible additions:

- apt/dnf package cache
- pip wheel cache
- cloned OpenStack repositories
- preinstalled common packages

This should be optional. The default path should remain source/ref driven by Ansible.

### 11.3 Image entrypoint

The image should boot systemd, not run DevStack directly.

Example intent:

```Dockerfile
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
```

DevStack execution remains Ansible-driven through `run-devstack`.

## 12. Provider Roles

### 12.1 `ard_oci_preflight`

Validates host runtime capabilities.

Checks:

- selected provider exists: Docker or Podman
- provider is rootful or running with sufficient privileges
- required Ansible collections are available
- `/dev/net/tun` exists when `kvm`, `ovn`, or `ovs` profile is used
- `/dev/kvm` exists when KVM is required
- nested virtualization is available if KVM is required
- `/lib/modules` exists when OVS/OVN profile needs it
- loop device support exists when storage profiles are enabled
- enough memory and disk are available
- selected subnet does not collide with obvious host networks where feasible

Preflight should fail early with actionable messages.

### 12.2 `ard_oci_image`

Builds or pulls the OCI image.

Inputs:

```yaml
ard_oci_image_source: build | pull | existing
ard_oci_image: localhost/ard-devstack-node:latest
ard_oci_image_context: images/ard-devstack-node
ard_oci_image_containerfile: Containerfile
```

Podman implementation:

- `containers.podman.podman_image`

Docker implementation:

- `community.docker.docker_image`

### 12.3 `ard_oci_network`

Creates the management network.

Inputs:

```yaml
ard_oci_network:
  name: ard-devstack
  subnet: 172.28.0.0/24
  gateway: 172.28.0.1
```

Responsibilities:

- create provider network
- support static IPv4 assignment
- optionally support IPv6 later
- expose network facts to node creation

### 12.4 `ard_oci_node`

Creates and starts each container node.

Responsibilities:

- translate node profiles to provider runtime arguments
- set container name and hostname
- attach to management network with static IP
- mount required devices and volumes
- inject SSH key material or provide a mechanism for `ensure_stack_user`
- start systemd
- wait for SSH

### 12.5 `ard_oci_inventory`

Discovers created containers and adds them to the active Ansible inventory.

Responsibilities:

- inspect each node
- determine management IP
- call `add_host`
- assign groups from node spec
- set `ansible_host`, `ansible_user`, `ansible_private_key_file`
- set `nodepool` facts
- set minimal `zuul` facts if needed by existing roles

This role is central to making the rest of ARD backend-independent.

### 12.6 `ard_oci_destroy`

Stops and removes containers and networks.

Inputs:

```yaml
ard_oci_destroy_volumes: true
ard_oci_destroy_images: false
```

Responsibilities:

- stop nodes
- remove nodes
- remove networks
- optionally remove volumes
- leave image cache intact unless explicitly requested

### 12.7 `ard_oci_collect_logs`

Collects logs from containers and the runtime host.

Responsibilities:

- collect container journal logs
- collect `/opt/stack/logs`
- collect DevStack `local.conf`, `.stackenv`, service logs
- collect runtime inspect output
- collect host network/device state relevant to debugging

This role should work even when the dynamic inventory is not present, by inspecting containers from the runtime host.

## 13. Playbook Flows

### 13.1 Create only

`ansible/playbooks/oci-create.yaml`

```yaml
- name: Create OCI DevStack nodes
  hosts: localhost
  gather_facts: true
  roles:
    - ard_oci_preflight
    - ard_oci_image
    - ard_oci_network
    - ard_oci_node
    - ard_oci_inventory
```

### 13.2 Deploy DevStack into existing containers

`ansible/playbooks/oci-deploy-devstack.yaml`

```yaml
- name: Discover OCI DevStack nodes
  hosts: localhost
  gather_facts: false
  roles:
    - ard_oci_inventory

- name: Deploy multinode DevStack
  import_playbook: ../deploy_multinode_devstack.yaml
```

The exact import path may need adjustment based on Ansible's playbook path rules.

### 13.3 Full local site flow

`ansible/playbooks/oci-site.yaml`

```yaml
- name: Create OCI DevStack nodes
  hosts: localhost
  gather_facts: true
  roles:
    - ard_oci_preflight
    - ard_oci_image
    - ard_oci_network
    - ard_oci_node
    - ard_oci_inventory

- name: Deploy multinode DevStack
  import_playbook: ../deploy_multinode_devstack.yaml

- name: Verify OCI DevStack deployment
  import_playbook: oci-verify.yaml
```

### 13.4 Destroy

`ansible/playbooks/oci-destroy.yaml`

```yaml
- name: Destroy OCI DevStack nodes
  hosts: localhost
  gather_facts: false
  roles:
    - ard_oci_collect_logs
    - ard_oci_destroy
```

## 14. Make Targets

Make targets should call Ansible playbooks directly. They should not implement provider logic themselves.

Example:

```make
OCI_PROVIDER ?= podman
OCI_INVENTORY ?= localhost,
OCI_EXTRA_VARS ?= ard_oci_provider=$(OCI_PROVIDER)

.PHONY: oci-image
oci-image:
	ansible-playbook -i $(OCI_INVENTORY) ansible/playbooks/oci-create.yaml \
		--tags image \
		-e $(OCI_EXTRA_VARS)

.PHONY: oci-create
oci-create:
	ansible-playbook -i $(OCI_INVENTORY) ansible/playbooks/oci-create.yaml \
		-e $(OCI_EXTRA_VARS)

.PHONY: oci-deploy
oci-deploy:
	ansible-playbook -i $(OCI_INVENTORY) ansible/playbooks/oci-deploy-devstack.yaml \
		-e $(OCI_EXTRA_VARS)

.PHONY: oci-verify
oci-verify:
	ansible-playbook -i $(OCI_INVENTORY) ansible/playbooks/oci-verify.yaml \
		-e $(OCI_EXTRA_VARS)

.PHONY: oci-destroy
oci-destroy:
	ansible-playbook -i $(OCI_INVENTORY) ansible/playbooks/oci-destroy.yaml \
		-e $(OCI_EXTRA_VARS)

.PHONY: oci-recreate
oci-recreate: oci-destroy oci-create

.PHONY: oci-site
oci-site:
	ansible-playbook -i $(OCI_INVENTORY) ansible/playbooks/oci-site.yaml \
		-e $(OCI_EXTRA_VARS)
```

These names can be shortened later, but the initial names should make the lifecycle obvious.

## 15. Molecule Integration

Use Molecule ansible-native or delegated mode so that Molecule calls the same playbooks as Make.

Example `molecule/oci-multinode/molecule.yml` shape:

```yaml
---
ansible:
  executor:
    backend: ansible-playbook
    args:
      ansible_playbook:
        - --inventory=localhost,
        - --extra-vars=ard_oci_provider=podman
  env:
    ANSIBLE_FORCE_COLOR: "true"
    ANSIBLE_STDOUT_CALLBACK: yaml
  playbooks:
    create: create.yml
    converge: converge.yml
    verify: verify.yml
    destroy: destroy.yml

scenario:
  test_sequence:
    - create
    - converge
    - verify
    - destroy

verifier:
  name: ansible
```

Then the scenario playbooks should be thin wrappers:

```yaml
# molecule/oci-multinode/create.yml
- import_playbook: ../../ansible/playbooks/oci-create.yaml
```

```yaml
# molecule/oci-multinode/converge.yml
- import_playbook: ../../ansible/playbooks/oci-deploy-devstack.yaml
```

```yaml
# molecule/oci-multinode/destroy.yml
- import_playbook: ../../ansible/playbooks/oci-destroy.yaml
```

This makes Molecule a workflow runner only.

## 16. Zuul Integration

Zuul should call the same provider roles.

Important constraint: dynamic inventory created with `add_host` in one Zuul playbook phase should not be assumed to persist into later phases.

Preferred patterns:

### 16.1 Create and deploy in one run playbook

```yaml
- name: Create OCI DevStack nodes
  hosts: container-host
  roles:
    - ard_oci_preflight
    - ard_oci_image
    - ard_oci_network
    - ard_oci_node
    - ard_oci_inventory

- name: Deploy DevStack
  import_playbook: ansible/deploy_multinode_devstack.yaml
```

### 16.2 Pre-run creates, run re-discovers

- `pre-run`: create containers
- `run`: inspect containers, call `ard_oci_inventory`, deploy DevStack
- `post-run`: collect logs by inspecting containers from the runtime host

The second model is useful if container creation should be visually separated in Zuul, but the run playbook must still rediscover hosts.

## 17. Docker Backend

Docker implementation should use `community.docker` modules.

Expected modules:

- `community.docker.docker_image`
- `community.docker.docker_network`
- `community.docker.docker_container`
- `community.docker.docker_container_info`

Docker-specific translation examples:

```yaml
privileged: true
cgroupns_mode: host
stop_signal: SIGRTMIN+3
devices:
  - /dev/kvm:/dev/kvm
  - /dev/net/tun:/dev/net/tun
volumes:
  - /sys/fs/cgroup:/sys/fs/cgroup:rw
  - /lib/modules:/lib/modules:ro
networks:
  - name: ard-devstack
    ipv4_address: 172.28.0.2
```

Docker is a good backend for validating OCI image behavior and runtime argument mapping.

## 18. Podman Backend

Podman implementation should use `containers.podman` modules.

Expected modules:

- `containers.podman.podman_image`
- `containers.podman.podman_network`
- `containers.podman.podman_container`
- `containers.podman.podman_container_info`

Podman-specific translation examples:

```yaml
privileged: true
systemd: always
device:
  - /dev/kvm:/dev/kvm
  - /dev/net/tun:/dev/net/tun
volume:
  - /sys/fs/cgroup:/sys/fs/cgroup:rw
  - /lib/modules:/lib/modules:ro
network: ard-devstack
ip: 172.28.0.2
```

Podman should be the preferred first backend if we want a future path to Quadlet and systemd-owned container lifecycle.

## 19. Future nspawn Backend

systemd-nspawn is out of the initial implementation but should remain compatible with the provider contract.

Modern systemd supports OCI in two relevant ways:

- `systemd-nspawn --oci-bundle=...` for OCI runtime bundles
- `importctl pull-oci REF NAME` for pulling OCI images into the systemd machine image store, available in systemd 260 and newer

A future nspawn backend should prefer:

```bash
importctl pull-oci --class=machine <oci-ref> <image-name>
machinectl clone <image-name> <node-name>
machinectl start <node-name>
```

Per-node configuration should use `.nspawn` files:

```text
/etc/systemd/nspawn/controller.nspawn
/etc/systemd/nspawn/compute1.nspawn
```

nspawn preflight should require:

```yaml
systemd_version >= 260
```

for direct OCI pull support. Older hosts would require a separate image conversion/import path or should be unsupported initially.

## 20. Persistence and Restart Model

Initial Docker/Podman mode should be transient:

```yaml
ard_oci_lifecycle: transient
```

Meaning:

- Ansible creates containers.
- Ansible destroys containers.
- Restartability is limited to runtime stop/start.
- Durable state lives in named volumes only if explicitly configured.

Future Podman Quadlet mode:

```yaml
ard_oci_lifecycle: quadlet
```

Meaning:

- Ansible writes `.container`, `.network`, and possibly `.volume` files.
- systemd owns lifecycle.
- containers can start on boot.
- developer can use `systemctl status ard-controller.service`.

Do not implement Quadlet first. It adds complexity before the node contract is proven.

## 21. State and Volume Strategy

Default behavior should be disposable.

Suggested volume model:

```yaml
ard_oci_volumes:
  controller:
    - name: ard-controller-opt-stack
      target: /opt/stack
    - name: ard-controller-var-log
      target: /var/log
```

Initial implementation may avoid persistent volumes entirely to reduce ambiguity. Add named volumes when restart behavior is tested.

Expected lifecycle commands:

- `make oci-create`: create fresh nodes
- `make oci-deploy`: run DevStack
- `make oci-destroy`: remove nodes
- `make oci-nuke`: remove nodes, networks, volumes, and optional images

## 22. Refactoring Existing ARD Logic

The main refactor is to separate provisioning from deployment.

Current Molecule/Vagrant provides:

- machines
- names
- groups
- IPs
- SSH access

`ard-oci` should replace only that part.

Existing roles to preserve:

- `ensure_stack_user`
- `prepare_dev_tools`
- `devstack_common`
- `devstack_controller`
- `devstack_compute`

Possible changes:

1. Make `devstack_common` tolerate container-specific hostname and network behavior.
2. Allow cache setup to be disabled or adjusted for containers.
3. Make firewall disabling conditional and harmless in containers.
4. Ensure `external_bridge_mtu` calculation works for container interfaces.
5. Avoid assuming libvirt/Vagrant-only properties in Molecule scenarios.

## 23. Testing and Verification

### 23.1 Provider smoke tests

Before running DevStack:

- image builds
- network exists
- controller container starts
- compute container starts
- SSH works to all nodes
- `ansible -m ping` works
- `/dev/kvm` visible when requested
- `/dev/net/tun` visible when requested
- systemd is PID 1

### 23.2 DevStack smoke tests

After deployment:

- `systemctl status 'devstack@*'`
- `openstack compute service list`
- `openstack network agent list` or OVN equivalent
- `nova-manage cell_v2 discover_hosts --verbose`
- boot a Cirros VM if profile supports Nova compute

### 23.3 Cleanup tests

- destroy after successful deployment
- destroy after failed container creation
- destroy after failed `stack.sh`
- recreate with same names and subnet

## 24. Phased Implementation Plan

### Phase 0: Document and pin the contract

- Add this design document.
- Document the current ARD Vagrant inventory contract.
- Identify variables used by controller and compute roles.

### Phase 1: Build minimal OCI image

- Add `images/ard-devstack-node/Containerfile`.
- Boot systemd in Docker/Podman.
- Start sshd.
- Verify Ansible SSH connectivity.

### Phase 2: Provider roles for one node

- Implement `ard_oci_preflight`.
- Implement `ard_oci_image`.
- Implement `ard_oci_network`.
- Implement `ard_oci_node` for one controller.
- Implement `ard_oci_inventory`.

### Phase 3: Multinode provider

- Add compute node support.
- Match current Molecule groups:
  - controller: `controller`, `switch`
  - computes: `compute`, `peers`, `subnode`
- Verify `ansible -m ping all`.

### Phase 4: Reuse existing ARD DevStack deployment

- Run `deploy_multinode_devstack.yaml` against OCI nodes.
- Fix only deployment assumptions that are invalid in containers.
- Avoid provider-specific logic in DevStack roles.

### Phase 5: Make targets

- Add `make oci-create`.
- Add `make oci-deploy`.
- Add `make oci-verify`.
- Add `make oci-destroy`.
- Add `make oci-site`.

### Phase 6: Molecule ansible-native scenario

- Add `molecule/oci-multinode`.
- Use same create/deploy/verify/destroy playbooks.
- Do not use Molecule-specific container provisioning unless needed for comparison.

### Phase 7: Zuul job prototype

- Add a non-voting experimental Zuul job.
- Provision containers on one assigned host.
- Rediscover dynamic inventory in the run playbook.
- Collect logs from the runtime host in post-run.

### Phase 8: Docker/Podman parity

- Implement or complete both providers.
- Ensure both consume the same `ard_oci_nodes` spec.
- Keep runtime-specific differences contained in provider roles.

### Phase 9: Advanced profiles

- Add `storage-loop`.
- Add `storage-lvm`.
- Add `container-engine`.
- Add optional persistent volumes.

### Phase 10: nspawn exploration

- Add preflight for systemd version.
- Test `importctl pull-oci` with the ARD node image.
- Add `.nspawn` rendering.
- Add `machinectl` lifecycle backend.

## 25. Risks and Open Questions

### 25.1 systemd in OCI containers

Docker and Podman require careful cgroup setup for systemd as PID 1. This needs testing across target hosts.

### 25.2 OVS and host contamination

OVS/OVN may require privileged access and host kernel modules. Cleanup must be reliable after failed runs.

### 25.3 Cinder LVM and iSCSI

Cinder LVM can affect host device mapper state. This should remain an explicit advanced profile.

### 25.4 SSH bootstrap

The provider must decide whether the image contains a pre-created `stack` user or whether Ansible creates it through an initial root SSH connection.

Initial recommendation: allow root SSH bootstrap, then reuse `ensure_stack_user`.

### 25.5 Dynamic inventory in Zuul

Zuul phases should rediscover container inventory rather than assuming `add_host` persists.

### 25.6 Log collection after failure

Post-failure log collection should work from the runtime host even if SSH into a container fails.

### 25.7 IP and network determinism

The provider should use static IPs and explicit container names to preserve existing ARD assumptions.

### 25.8 Future nspawn image compatibility

The OCI image must remain a bootable OS-style image if it is expected to work with nspawn later.

## 26. Recommended Initial Defaults

```yaml
ard_oci_provider: podman
ard_oci_lifecycle: transient
ard_oci_connection: ssh
ard_oci_image_source: build
ard_oci_image: localhost/ard-devstack-node:latest
ard_oci_destroy_volumes: true
ard_oci_destroy_images: false
```

Default topology:

```yaml
ard_oci_nodes:
  - name: controller
    hostname: controller
    ip: 172.28.0.2
    groups: [controller, switch]
    profiles: [systemd, ssh, kvm, ovn]

  - name: compute1
    hostname: compute1
    ip: 172.28.0.3
    groups: [compute, peers, subnode]
    profiles: [systemd, ssh, kvm, ovn]
```

## 27. Summary

`ard-oci` should be a provider layer, not a replacement for the existing ARD DevStack deployment logic.

The provider layer creates OCI-backed system-container nodes, discovers their addresses, and adds them to Ansible inventory with the same groups and facts currently provided by Vagrant/Molecule or Zuul/nodepool.

Make, Molecule, and Zuul should all call the same Ansible roles and playbooks:

```text
create containers -> add inventory -> deploy DevStack -> verify -> collect logs -> destroy
```

Docker and Podman should be implemented first. Podman is the preferred first backend if future Quadlet support is desired. Docker can be added with the same node spec. systemd-nspawn remains a future backend, enabled by modern systemd OCI support but requiring additional image and machine lifecycle work.
