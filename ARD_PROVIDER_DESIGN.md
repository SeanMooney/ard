# ARD Provider Design Plan

## 1. Purpose

This document defines a short-term provider framework for ARD focused on VM-backed DevStack environments. It supersedes the short-term direction of `ARD_OCI_DESIGN.md`, which should be treated as deferred container-provider work.

The immediate goal is to replace the current Molecule/Vagrant/libvirt provisioning dependency with provider roles that can create DevStack-capable nodes using either:

1. local libvirt; or
2. KubeVirt / OpenShift Virtualization on a remote OpenShift cluster.

Docker, Podman, OCI system containers, and systemd-nspawn remain possible future providers, but they are not the initial focus.

## 2. Goals

1. Reproduce the current ARD Vagrant/libvirt workflow without Vagrant.
2. Add OpenShift Virtualization as an additional VM hosting option.
3. Preserve existing ARD DevStack deployment roles and playbooks.
4. Keep Make and Molecule using the same Ansible provider roles.
5. Keep provider-specific logic isolated to provider roles.
6. Make provider-created VMs look like the current ARD/Zuul multinode inventory contract.
7. Support both all-in-one and multinode DevStack topologies.
8. Use KubeVirt pod-network/masquerade mode first, without requiring Multus.
9. For KubeVirt multinode, rely on DevStack/Linux bridge/OVS/OVN overlay networking with VXLAN tunnels when needed.

## 3. Non-goals

- Do not implement Docker/Podman/nspawn providers in the first phase.
- Do not require Vagrant for the new provider flows.
- Do not require Multus or secondary L2 networks for initial KubeVirt support.
- Do not replace DevStack with Kolla, Kolla-Ansible, or OpenStack-Helm.
- Do not split OpenStack services into individual containers.
- Do not modify DevStack roles to know whether nodes came from libvirt or KubeVirt.

## 4. Existing ARD Contract to Preserve

Current ARD Molecule/Vagrant scenarios create machines with stable names and groups, then ARD deploys DevStack through existing roles.

The important inventory shape is:

```yaml
controller:
  groups:
    - controller
    - switch

compute1:
  groups:
    - compute
    - peers
    - subnode

compute2:
  groups:
    - compute
    - peers
    - subnode
```

Existing roles and playbooks to preserve:

- `ansible/deploy_multinode_devstack.yaml`
- `ansible/devstack_common.yaml`
- `ansible/roles/devstack_common/`
- `ansible/roles/devstack_controller/`
- `ansible/roles/devstack_compute/`
- upstream/openstack roles such as `write-devstack-local-conf` and `run-devstack`

The provider framework should replace only the provisioning layer.

## 5. High-level Architecture

```text
make / molecule / zuul
        |
        v
ARD provider playbooks
        |
        v
provider dispatcher roles
        |
        v
libvirt provider OR kubevirt provider
        |
        v
VMs with SSH access
        |
        v
dynamic Ansible inventory
        |
        v
existing ARD DevStack deployment roles
        |
        v
DevStack inside VMs
```

The provider's job ends when:

1. VMs exist.
2. SSH works.
3. Ansible inventory has the expected names, groups, and facts.

After that, the existing ARD DevStack roles take over.

## 6. Proposed Repository Layout

```text
ARD_PROVIDER_DESIGN.md
ARD_OCI_DESIGN.md                 # deferred/future container-provider design
Makefile

ansible/
  playbooks/
    ard-render.yaml
    ard-apply.yaml
    ard-create.yaml              # compatibility wrapper for ard-apply.yaml
    ard-deploy-devstack.yaml
    ard-verify.yaml
    ard-destroy.yaml
    ard-cleanup.yaml
    ard-collect-logs.yaml
    ard-site.yaml
    ard-kubevirt-ensure-resources.yaml

  files/
    kubevirt/
      devstack-instancetype-preference.yaml

  roles/
    ard_provider_render/
    ard_provider_preflight/
    ard_provider_image/
    ard_provider_network/
    ard_provider_node/
    ard_provider_inventory/
    ard_provider_state/
    ard_provider_destroy/
    ard_provider_cleanup/
    ard_provider_collect_logs/

    ard_libvirt_preflight/
    ard_libvirt_image/
    ard_libvirt_network/
    ard_libvirt_node/
    ard_libvirt_inventory/
    ard_libvirt_destroy/
    ard_libvirt_collect_logs/

    ard_kubevirt_preflight/
    ard_kubevirt_image/
    ard_kubevirt_network/
    ard_kubevirt_node/
    ard_kubevirt_inventory/
    ard_kubevirt_destroy/
    ard_kubevirt_collect_logs/

deployments/
  <deployment-name>/
    deployment.yaml              # provider, topology, image/flavor defaults
    nodes.yaml                   # rendered node list; user-tweakable
    devstack/
      common.yaml                # upstream/Zuul-style Ansible vars shared by all nodes
      group_vars/
        controller.yaml          # controller group vars using existing controller_* names
        compute.yaml             # compute group vars using existing compute_* names
      host_vars/
        controller.yaml          # optional per-node Ansible vars
        compute1.yaml
    inventory.yaml               # generated provider inventory
    provider-state.yaml          # provider resource names/ids for destroy
    rendered/
      kubevirt/
      libvirt/
    logs/

molecule/
  libvirt-multinode/
    molecule.yml
    create.yml
    converge.yml
    verify.yml
    destroy.yml

  kubevirt-multinode/
    molecule.yml
    create.yml
    converge.yml
    verify.yml
    destroy.yml
```

The generic `ard_provider_*` roles dispatch to provider-specific roles according to `ard_provider`.

Example dispatcher pattern:

```yaml
- name: Run provider-specific node creation
  include_role:
    name: "ard_{{ ard_provider }}_node"
```

## 7. Provider-neutral Variables

### 7.1 Provider selection

```yaml
ard_provider: libvirt
```

Supported initial values:

```yaml
ard_provider: libvirt
ard_provider: kubevirt
```

Deferred/future values:

```yaml
ard_provider: podman
ard_provider: docker
ard_provider: nspawn
```

### 7.2 Portable image, flavor, and preference model

ARD nodes should describe the desired guest in provider-neutral terms, then let each provider translate those terms into its native implementation.

The portable model has three layers:

1. `ard_images`: boot image definitions, always assumed to be cloud images that support cloud-init.
2. `ard_flavors`: sizing and CPU capability definitions.
3. `ard_vm_preferences`: machine/device preferences that are meaningful across providers where possible.

Default image and local cache:

```yaml
ard_default_image: debian-13
ard_image_cache_dir: "{{ lookup('env', 'XDG_CACHE_HOME') | default('~/.cache', true) }}/ard/images"
ard_image_download: true
ard_image_checksum_required: false

ard_images:
  debian-13:
    os_family: debian
    version: "13"
    cloud_init: true
    provider:
      kubevirt:
        source_kind: DataVolume
        name: debian-13-2026-05-20
        namespace: "{{ ard_kubevirt_image_namespace | default(ard_kubevirt_namespace) }}"
      libvirt:
        url: https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
        alternate_urls:
          - https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2
        name: debian-13
        format: qcow2
        cloud_init_datasource: NoCloud

  ubuntu-24.04:
    os_family: ubuntu
    version: "24.04"
    cloud_init: true
    provider:
      libvirt:
        url: https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
        name: ubuntu-24.04
        format: qcow2
        cloud_init_datasource: NoCloud

  ubuntu-26.04:
    os_family: ubuntu
    version: "26.04"
    cloud_init: true
    provider:
      libvirt:
        # Keep configurable until the Ubuntu 26.04 codename and final cloud
        # image URL are available.
        url: "{{ ard_libvirt_ubuntu_26_04_cloud_image_url }}"
        name: ubuntu-26.04
        format: qcow2
        cloud_init_datasource: NoCloud
```

Both initial VM providers rely on cloud images plus cloud-init for hostname, the `stack` user, sudo, Python bootstrap, and SSH key injection. Provider image roles should download configured libvirt cloud images into `ard_image_cache_dir` when missing, optionally validate checksums when configured, and never mutate cached base images. The default cache path follows XDG cache conventions via `$XDG_CACHE_HOME`, falling back to `~/.cache`. Per-deployment disks are overlays or copies derived from the cached base image.

Default flavors:

```yaml
ard_default_controller_flavor: devstack-control
ard_default_compute_flavor: devstack-compute

ard_flavors:
  devstack-control:
    description: All-in-one or controller node flavor.
    vcpus: 8
    memory: 16Gi
    nested_virt: true
    provider:
      kubevirt:
        instancetype: devstack-8c16g
      libvirt:
        vcpus: 8
        memory_mb: 16384
        cpu_mode: host-passthrough

  devstack-compute:
    description: Compute node flavor for multinode topologies.
    vcpus: 8
    memory: 8Gi
    nested_virt: true
    provider:
      kubevirt:
        instancetype: devstack-8c8g
      libvirt:
        vcpus: 8
        memory_mb: 8192
        cpu_mode: host-passthrough
```

Default VM preference:

```yaml
ard_default_vm_preference: devstack

ard_vm_preferences:
  devstack:
    provider:
      kubevirt:
        preference: devstack
      libvirt:
        machine_type: q35
        disk_bus: virtio
        interface_model: virtio
        rng: true
        efi_secure_boot: false
```

For KubeVirt, `devstack-control` maps to `VirtualMachineInstancetype/devstack-8c16g`, `devstack-compute` maps to `VirtualMachineInstancetype/devstack-8c8g`, and all DevStack VMs use `VirtualMachinePreference/devstack` by default.

For libvirt, the same flavor and preference names are translated into domain CPU, memory, machine, disk, interface, and RNG settings.

### 7.3 Node topology

```yaml
ard_nodes:
  - name: controller
    hostname: controller
    groups:
      - controller
      - switch
    image: debian-13
    flavor: devstack-control
    preference: devstack
    networks:
      - name: ard-mgmt
        ip: 192.168.96.2
    profiles:
      - ssh
      - nested_virt
      - ovn

  - name: compute1
    hostname: compute1
    groups:
      - compute
      - peers
      - subnode
    image: debian-13
    flavor: devstack-compute
    preference: devstack
    networks:
      - name: ard-mgmt
        ip: 192.168.96.3
    profiles:
      - ssh
      - nested_virt
      - ovn

  - name: compute2
    hostname: compute2
    groups:
      - compute
      - peers
      - subnode
    image: debian-13
    flavor: devstack-compute
    preference: devstack
    networks:
      - name: ard-mgmt
        ip: 192.168.96.4
    profiles:
      - ssh
      - nested_virt
      - ovn
```

Provider roles translate this specification into libvirt domains or KubeVirt VirtualMachines.

### 7.4 Deployment workspace model

ARD should support a Molecule-like workflow where the basic shape of a deployment is rendered once to disk, edited by the user, then applied to either provider. The on-disk unit of state is a deployment subdirectory:

```text
deployments/<deployment-name>/
  deployment.yaml
  nodes.yaml
  devstack/
    common.yaml
    group_vars/
      controller.yaml
      compute.yaml
    host_vars/
      controller.yaml
      compute1.yaml
  inventory.yaml
  provider-state.yaml
  rendered/
    kubevirt/
    libvirt/
  logs/
```

The deployment name is derived from the subfolder name by default. For example, `deployments/devstack-a/` implies:

```yaml
ard_deployments_dir: deployments
ard_deployment_dir: deployments/devstack-a
ard_deployment_name: devstack-a
ard_resource_name_prefix: ard-devstack-a
```

If `ard_deployment_name` is passed explicitly, it must match the basename of `ard_deployment_dir` unless the user also sets an explicit override for advanced workflows.

The workflow is:

1. **Render**: create `deployments/<deployment-name>/` from provider-neutral presets, provider profiles, service profiles, and optional overlays. This does not contact libvirt or OpenShift.
2. **Customize**: keep custom intent in a render file or overlay, rather than editing generated concrete files directly. Render is intentionally kustomize-like but simpler: presets are bases, overlays are ordinary YAML dictionaries, and later layers deep-merge into earlier layers.
3. **Apply**: read the deployment folder, create or update provider resources, wait for SSH and cloud-init, generate `inventory.yaml`, and write `provider-state.yaml`.
4. **Destroy**: use `provider-state.yaml`, the deployment name, and provider labels/name prefixes to destroy provider resources. Keep the deployment folder and logs.
5. **Cleanup**: remove generated local deployment artifacts after destroy when the user no longer needs rendered inputs or state.

Render composition order is:

```text
role defaults
  -> branch preset
  -> topology preset
  -> service profiles, in requested order
  -> provider profile
  -> render intent file
  -> deployment-local overlay file
  -> CLI / Make extra-vars
```

The intent file is small and should be the primary committed interface for Molecule scenarios and reusable examples:

```yaml
# render.yaml
ard_provider: libvirt
ard_provider_profile: local-libvirt
ard_target_branch: master
ard_topology: one-controller-two-compute
ard_service_profiles:
  - devstack
  - ovn
  - tempest
```

Topology presets are named convenience bases such as `all-in-one`, `one-controller-one-compute`, and `one-controller-two-compute`. They normalize into counts and roles, and advanced users may override the normalized values with `ard_topology_overrides` when a curated name is close but not exact.

Generated concrete files such as `deployment.yaml`, `nodes.yaml`, and `devstack/*.yaml` are render output. They should include a generated-file header and may be overwritten by subsequent renders. Local customizations belong in the render intent or an overlay such as `overrides/render.yaml`.

The supported explicit overlay dictionary is:

```yaml
ard_render_overrides:
  provider_defaults:
    image: ubuntu-24.04
    controller_flavor: devstack-control
    compute_flavor: devstack-compute
    vm_preference: devstack
  topology:
    compute_count: 2
  devstack:
    common:
      enable_ceph: true
    controller:
      controller_localrc_extra:
        DEBUG_LIBVIRT_COREDUMPS: true
    compute:
      compute_localrc_extra: {}
```

For command-line convenience, `ard_render_image`, `ard_render_controller_flavor`, `ard_render_compute_flavor`, and `ard_render_vm_preference` can override the composed provider defaults without changing the eventual provider input names written to `deployment.yaml`.

Example deployment inputs:

```yaml
# deployments/devstack-a/deployment.yaml
ard_provider: kubevirt
ard_default_image: debian-13
ard_default_controller_flavor: devstack-control
ard_default_compute_flavor: devstack-compute
ard_default_vm_preference: devstack
ard_kubevirt_namespace: ard-devstack
ard_kubevirt_storage_class: null
```

```yaml
# deployments/devstack-a/nodes.yaml
ard_nodes:
  - name: controller
    groups: [controller, switch]
    image: debian-13
    flavor: devstack-control
    preference: devstack
  - name: compute1
    groups: [compute, peers, subnode]
    image: debian-13
    flavor: devstack-compute
    preference: devstack
```

```yaml
# deployments/devstack-a/devstack/common.yaml
# Keep this close to Zuul job vars and the existing ARD/devstack role inputs.
devstack_branch: master
run_devstack: true
enable_ceph: false
configure_vdpa: false
```

```yaml
# deployments/devstack-a/devstack/group_vars/controller.yaml
controller_localrc_extra:
  ENABLE_TENANT_TUNNELS: true
  ENABLE_TENANT_VLANS: false
controller_local_conf_extra: {}
controller_services_extra: {}
```

```yaml
# deployments/devstack-a/devstack/group_vars/compute.yaml
compute_localrc_extra:
  ENABLE_TENANT_TUNNELS: true
  ENABLE_TENANT_VLANS: false
compute_local_conf_extra: {}
compute_services_extra: {}
```

```yaml
# deployments/devstack-a/devstack/host_vars/compute1.yaml
compute_localrc_extra:
  LIBVIRT_TYPE: qemu
```

The deployment name must be affixed to every created provider resource so multiple copies of the same rendered scenario can coexist. Provider resource names should use `ard-<deployment-name>-<inventory-name>`, for example `ard-devstack-1-controller`, while Ansible inventory hostnames remain the logical ARD names.

Required resource identity contract:

```yaml
metadata_or_tags:
  app.kubernetes.io/part-of: ard
  app.kubernetes.io/instance: devstack-a
  ard.openstack.org/deployment: devstack-a
  ard.openstack.org/provider: kubevirt
  ard.openstack.org/node: controller
```

For KubeVirt, apply these labels to deployment-scoped `VirtualMachine`, per-node `DataVolume`/PVC, cloud-init `Secret` if used, SSH `Service`, and any generated support resources. Shared setup resources such as `VirtualMachineInstancetype/devstack-8c16g`, `VirtualMachineInstancetype/devstack-8c8g`, and `VirtualMachinePreference/devstack` are not deployment-scoped unless explicitly rendered into the deployment namespace as part of setup.

For libvirt, include the deployment name in domains, volumes, cloud-init seed ISOs, and generated network names where applicable. Example storage layout:

```text
$XDG_STATE_HOME/ard/libvirt/images/<deployment-name>/  # or ~/.local/state/ard/libvirt/images when XDG_STATE_HOME is unset
  controller.qcow2
  controller-seed.iso
  compute1.qcow2
  compute1-seed.iso
```

`provider-state.yaml` should record native resource names and identifiers, but destroy must also support a label/name-prefix fallback so cleanup is possible if state is partially missing.

### 7.5 DevStack local.conf input layering

A deployment must not assume one `local.conf` for all nodes. It also should not invent a parallel local.conf input schema as the primary interface. Because ARD reuses the upstream DevStack Ansible roles used by Zuul CI jobs, the deployment workspace should preserve the same Ansible variable contract wherever possible.

The alignment target is: relevant Zuul job vars should be copyable or lightly adapted into the deployment workspace, while provider provisioning inputs remain separate in `deployment.yaml` and `nodes.yaml`.

The existing integration point is already present:

- `ansible/roles/devstack_controller/tasks/main.yml` calls `write-devstack-local-conf` using `controller_localrc`, `controller_localrc_extra`, `controller_local_conf`, `controller_local_conf_extra`, `controller_services`, and `controller_services_extra`.
- `ansible/roles/devstack_compute/tasks/main.yml` calls `write-devstack-local-conf` using `compute_localrc`, `compute_localrc_extra`, `compute_local_conf`, `compute_local_conf_extra`, `compute_services`, and `compute_services_extra`.

The provider workflow should add a provider-neutral `ard_devstack_config` loader before `devstack_controller.yaml` and `devstack_compute.yaml`. That loader reads normal Ansible-shaped var files from the deployment workspace and exposes them using the same variable names consumed by the existing roles. It does not render `local.conf` itself and does not replace `write-devstack-local-conf`.

Recommended workspace shape:

```text
deployments/<name>/devstack/
  common.yaml
  group_vars/
    controller.yaml
    compute.yaml
  host_vars/
    controller.yaml
    compute1.yaml
```

Merge order for each host:

```text
existing role defaults
  -> deployments/<name>/devstack/common.yaml
  -> deployments/<name>/devstack/group_vars/<group>.yaml
  -> deployments/<name>/devstack/host_vars/<inventory_hostname>.yaml
  -> inventory vars / CLI extra-vars / Zuul job vars
```

The merged values should use the existing ARD/upstream-compatible variables directly:

```yaml
# controller hosts
controller_localrc_extra
controller_local_conf_extra
controller_services_extra
controller_devstack_plugins

# compute hosts
compute_localrc_extra
compute_local_conf_extra
compute_services_extra
compute_devstack_plugins
```

Later layers override or deep-merge according to the same `combine` strategy already used by `devstack_controller` and `devstack_compute`. This keeps DevStack rendering provider-neutral and node-aware while preserving the current upstream `write-devstack-local-conf` integration and making local CI reproduction the default design target.

## 8. Inventory Contract

Every provider must add nodes to active Ansible inventory with the same effective facts.

For `controller`:

```yaml
inventory_hostname: controller
ansible_host: 192.168.96.2
ansible_user: stack
ansible_private_key_file: ~/.ssh/id_ed25519_stack
ard_deployment_name: devstack-a
ard_provider_resource_name: ard-devstack-a-controller
nodepool:
  private_ipv4: 192.168.96.2
  public_ipv4: 192.168.96.2
zuul:
  executor:
    log_root: /tmp/zuul_logs
    work_root: /tmp/work_root
```

For `compute1`:

```yaml
inventory_hostname: compute1
ansible_host: 192.168.96.3
ansible_user: stack
ansible_private_key_file: ~/.ssh/id_ed25519_stack
nodepool:
  private_ipv4: 192.168.96.3
  public_ipv4: 192.168.96.3
```

Groups come from `ard_nodes[*].groups`.

For deployment workspaces, `inventory.yaml` is generated inside `deployments/<deployment-name>/` and can be re-read by later apply, deploy, verify, collect-log, and destroy phases. Inventory hostnames remain stable logical names such as `controller` and `compute1`; provider resource names are tracked separately through `ard_provider_resource_name` and `provider-state.yaml`.

This lets existing ARD defaults continue to evaluate expressions such as:

```yaml
SERVICE_HOST: "{{ hostvars[groups['controller'][0]]['nodepool']['private_ipv4'] }}"
HOST_IP: "{{ hostvars[inventory_hostname]['nodepool']['private_ipv4'] }}"
```

## 9. Common Provider Playbooks

### 9.1 `ard-render.yaml`

Creates or refreshes a deployment workspace from defaults. It writes `deployment.yaml`, `nodes.yaml`, and the layered files under `devstack/` without creating provider resources.

```yaml
- name: Render ARD deployment workspace
  hosts: localhost
  gather_facts: false
  roles:
    - ard_provider_render
```

### 9.2 `ard-apply.yaml` / `ard-create.yaml`

Reads a deployment workspace, creates provider resources, and writes dynamic inventory/state. `ard-create.yaml` can remain as a compatibility wrapper for users and Molecule scenarios that already expect a create phase.

```yaml
- name: Apply ARD provider deployment
  hosts: localhost
  gather_facts: true
  roles:
    - ard_provider_preflight
    - ard_provider_image
    - ard_provider_network
    - ard_provider_node
    - ard_provider_inventory
    - ard_provider_state
```

### 9.3 `ard-deploy-devstack.yaml`

Re-discovers provider inventory and deploys DevStack.

```yaml
- name: Discover ARD provider nodes
  hosts: localhost
  gather_facts: false
  roles:
    - ard_provider_inventory

- name: Load deployment DevStack config
  hosts: all
  gather_facts: false
  roles:
    - ard_devstack_config

- name: Deploy ARD multinode DevStack
  import_playbook: ../deploy_multinode_devstack.yaml
```

### 9.4 `ard-site.yaml`

Full local flow. It can render a deployment workspace if needed, apply it, deploy DevStack, and verify.

```yaml
- import_playbook: ard-render.yaml
- import_playbook: ard-apply.yaml
- import_playbook: ard-deploy-devstack.yaml

- name: Verify ARD deployment
  import_playbook: ard-verify.yaml
```

### 9.5 `ard-destroy.yaml`

Collects logs and destroys provider resources for a deployment workspace. It keeps the deployment folder so inputs, generated inventory, provider state, and logs remain available for inspection.

```yaml
- name: Destroy ARD provider deployment
  hosts: localhost
  gather_facts: false
  roles:
    - ard_provider_inventory
    - ard_provider_collect_logs
    - ard_provider_destroy
```

### 9.6 `ard-cleanup.yaml`

Removes local deployment workspace state after destroy.

```yaml
- name: Cleanup ARD deployment workspace
  hosts: localhost
  gather_facts: false
  roles:
    - ard_provider_cleanup
```

Provider inventory should be rediscovered at the start of every playbook that needs it. Do not rely on `add_host` from an earlier execution persisting across Make, Molecule, or Zuul phases.

## 10. Libvirt Provider Design

The libvirt provider is the first target because it most directly replaces the current Vagrant/libvirt workflow.

### 10.1 Provider variables

```yaml
ard_provider: libvirt

ard_libvirt_uri: qemu:///system
ard_libvirt_pool: ard
ard_libvirt_network_name: ard-mgmt
ard_libvirt_network_cidr: 192.168.96.0/24
ard_libvirt_network_gateway: 192.168.96.1
ard_image_cache_dir: "{{ lookup('env', 'XDG_CACHE_HOME') | default('~/.cache', true) }}/ard/images"
ard_image_download: true
ard_image_checksum_required: false
ard_libvirt_image_dir: "{{ lookup('env', 'XDG_STATE_HOME') | default('~/.local/state', true) }}/ard/libvirt/images"
ard_libvirt_debian_13_cloud_image_url: https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
ard_libvirt_debian_13_alternate_cloud_image_url: https://cloud.debian.org/images/cloud/trixie/latest/debian-13-nocloud-amd64.qcow2
ard_libvirt_ubuntu_24_04_cloud_image_url: https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
ard_libvirt_ubuntu_26_04_cloud_image_url: null
ard_default_image: debian-13
ard_default_controller_flavor: devstack-control
ard_default_compute_flavor: devstack-compute
ard_default_vm_preference: devstack
```

### 10.2 Roles

```text
ard_libvirt_preflight
ard_libvirt_image
ard_libvirt_network
ard_libvirt_node
ard_libvirt_inventory
ard_libvirt_destroy
ard_libvirt_collect_logs
```

### 10.3 Preflight

Check:

- libvirt daemon is available
- Ansible can connect to `ard_libvirt_uri`
- `qemu-img` is installed
- cloud-init tooling is available, e.g. `cloud-localds` or equivalent
- selected network CIDR does not collide with obvious host networks
- enough disk exists for overlays
- enough memory/CPU exists for requested nodes
- nested virtualization is enabled if `nested_virt` is requested

### 10.4 Image handling

Preferred image model:

1. Resolve `ard_nodes[*].image` through `ard_images`.
2. Download or reuse the base cloud image from `ard_image_cache_dir`.
3. Optionally validate the cached image checksum when configured.
4. Create a qcow2 overlay per node under `ard_libvirt_image_dir/<deployment-name>/`.
5. Create a cloud-init NoCloud/config-drive seed ISO per node.
6. Boot each VM from its overlay plus seed.

The cache is shared across deployments and must not be mutated. Destroy removes deployment overlays and seed ISOs by default, but leaves cached base images intact.

Example:

```text
$XDG_CACHE_HOME/ard/images/  # or ~/.cache/ard/images when XDG_CACHE_HOME is unset
  debian-13-genericcloud-amd64.qcow2
  noble-server-cloudimg-amd64.img

$XDG_STATE_HOME/ard/libvirt/images/devstack-a/  # or ~/.local/state/ard/libvirt/images/devstack-a when XDG_STATE_HOME is unset
  controller.qcow2
  controller-seed.iso
  compute1.qcow2
  compute1-seed.iso
```

### 10.5 Cloud-init

Cloud-init should provide:

- hostname
- stack user
- sudo permissions
- SSH authorized key
- static network config or DHCP client config
- optional package bootstrap if needed

Example user-data intent:

```yaml
#cloud-config
hostname: controller
users:
  - name: stack
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-ed25519 ...
packages:
  - python3
  - sudo
  - git
  - rsync
```

### 10.6 Networking

The libvirt provider should create a NATed management network by default.

Example:

```yaml
ard_libvirt_network_name: ard-mgmt
ard_libvirt_network_cidr: 192.168.96.0/24
ard_libvirt_network_gateway: 192.168.96.1
```

Static IPs are preferred for reproducibility. DHCP reservations are also acceptable if inventory discovery is reliable.

For multinode DevStack, the libvirt management network can carry service traffic and overlay tunnel traffic. DevStack can configure Linux bridge, OVS, or OVN inside the VMs as needed.

### 10.7 Node creation

Preferred implementation:

- render libvirt network and domain XML from Jinja templates
- define/start resources with `virsh`
- keep rendered XML under `deployments/<deployment-name>/rendered/libvirt/` for review and debugging

Possible future alternatives:

- `community.libvirt.virt`
- `community.libvirt.virt_net`
- `community.libvirt.virt_pool`

`virt-install` should not be used by default. It is mostly a convenience wrapper around libvirt XML creation, and templated XML is more reviewable and reproducible for ARD provider work.

Required domain properties:

- memory from the resolved portable flavor, e.g. `ard_flavors[flavor].provider.libvirt.memory_mb`
- vCPUs from the resolved portable flavor, e.g. `ard_flavors[flavor].provider.libvirt.vcpus`
- CPU mode from the resolved portable flavor, e.g. `ard_flavors[flavor].provider.libvirt.cpu_mode`
- machine/device defaults from the resolved portable preference, e.g. q35, virtio disk/interface, RNG, and secure-boot behavior
- disk overlay per node
- cloud-init seed disk
- network interface attached to `ard_libvirt_network_name`

### 10.8 Console logging

Libvirt domains should keep an interactive PTY serial console for `virsh console` / virt-manager and also log serial output to the deployment's XDG state directory:

```text
$XDG_STATE_HOME/ard/libvirt/images/<deployment-name>/<node>-console.log
```

The domain XML should use a Jinja-rendered serial device with a libvirt `<log file=... append='on'/>` element so early boot, kernel, cloud-init, and getty output are available even if virt-manager is opened after the output was produced.

### 10.9 Inventory

Inventory can be built from:

1. static IPs from `ard_nodes`; or
2. libvirt DHCP leases; or
3. guest agent data later.

Initial implementation should prefer static IPs because ARD already assumes deterministic addresses in several places.

## 11. KubeVirt / OpenShift Virtualization Provider Design

The KubeVirt provider allows ARD to create DevStack-capable VMs on a remote OpenShift cluster.

The initial networking mode is **pod network / masquerade**. Do not require Multus or a secondary L2 network at first.

For multinode DevStack, rely on the VM management/pod-network IP path for node-to-node communication. DevStack's internal Linux bridge, OVS, or OVN configuration can create tenant networking and VXLAN tunnels inside the VMs when needed.

### 11.1 Provider variables

```yaml
ard_provider: kubevirt

ard_kubevirt_namespace: ard-devstack
# Omit by default so PVC/DataVolume creation can inherit the namespace,
# boot source, CDI, or cluster default StorageClass. Set only when a scenario
# needs to force a specific class.
ard_kubevirt_storage_class: null
ard_kubevirt_network_mode: masquerade
ard_kubevirt_ssh_access: nodeport
ard_kubevirt_image_source: datavolume
ard_kubevirt_default_image: debian-13
ard_kubevirt_default_controller_flavor: devstack-control
ard_kubevirt_default_compute_flavor: devstack-compute
ard_kubevirt_default_preference: devstack
ard_kubevirt_ensure_instancetype_resources: false
ard_kubevirt_delete_namespace: false
```

Allowed initial SSH access modes:

```yaml
ard_kubevirt_ssh_access: nodeport      # expose each VM SSH via a NodePort Service
ard_kubevirt_ssh_access: loadbalancer  # expose each VM SSH via LoadBalancer Service, if available
ard_kubevirt_ssh_access: port_forward  # local/dev only; less suitable for long-running automation
ard_kubevirt_ssh_access: bastion       # future mode using a bastion pod/VM
```

Initial recommendation:

```yaml
ard_kubevirt_network_mode: masquerade
ard_kubevirt_ssh_access: nodeport
```

### 11.2 Roles

```text
ard_kubevirt_preflight
ard_kubevirt_image
ard_kubevirt_network
ard_kubevirt_node
ard_kubevirt_inventory
ard_kubevirt_destroy
ard_kubevirt_collect_logs
```

### 11.3 Bundled instancetype and preference resources

ARD should carry the default KubeVirt instancetype and preference definitions in:

```text
ansible/files/kubevirt/devstack-instancetype-preference.yaml
```

These definitions are intentionally namespaced `VirtualMachineInstancetype` and `VirtualMachinePreference` resources so they can be applied to the target ARD namespace. The provider should use existing resources when they are already present. It should not create or update them implicitly unless `ard_kubevirt_ensure_instancetype_resources` is enabled or an explicit setup target/playbook is run.

Resource defaults:

- `VirtualMachineInstancetype/devstack-8c16g`: 8 guest CPUs, host-passthrough CPU model, automatic IOThreads, 16Gi memory.
- `VirtualMachineInstancetype/devstack-8c8g`: 8 guest CPUs, host-passthrough CPU model, automatic IOThreads, 8Gi memory.
- `VirtualMachinePreference/devstack`: q35, virtio disk/interface, RNG, KVM preference, EFI with secure boot disabled, and core CPU topology.

### 11.4 Preflight

Check:

- kubeconfig is available
- selected namespace exists or can be created
- OpenShift Virtualization/KubeVirt APIs are available
- CDI APIs are available if using DataVolumes
- selected StorageClass exists, if `ard_kubevirt_storage_class` is set
- caller has RBAC for required resources
- VM feature gates are adequate for requested profiles
- SSH exposure mode is possible
- nested virtualization is available if `nested_virt` is requested and Nova should use KVM

Relevant Kubernetes/OpenShift resource kinds:

- `VirtualMachine`
- `VirtualMachineInstance`
- `DataVolume`
- `PersistentVolumeClaim`
- `Secret`
- `Service`
- possibly `Route` for web endpoints later, but not required for SSH

### 11.5 Image handling

Initial image flow:

1. Resolve `ard_nodes[*].image` through `ard_images`.
2. Prefer an existing KubeVirt/CDI boot source, DataVolume, or PVC when present.
3. For the default `debian-13` image, assume an existing `DataVolume`/PVC named `debian-13-2026-05-20` unless the scenario overrides it.
4. Clone or create one PVC per VM root disk from that source.
5. Attach cloud-init data via `cloudInitNoCloud`.

Example existing image reference:

```yaml
ard_images:
  debian-13:
    os_family: debian
    version: "13"
    cloud_init: true
    provider:
      kubevirt:
        source_kind: DataVolume
        name: debian-13-2026-05-20
        namespace: "{{ ard_kubevirt_image_namespace | default(ard_kubevirt_namespace) }}"
```

When creating PVCs or DataVolumes, the provider should omit `storageClassName` by default. This lets the namespace, CDI boot source, or cluster default choose the StorageClass. `ard_kubevirt_storage_class` is an explicit override for environments that need one.

The provider should avoid re-importing the base image unless requested.

### 11.6 VM creation

Each ARD node maps to one KubeVirt `VirtualMachine`.

Example shape:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: controller
  namespace: ard-devstack
  labels:
    app.kubernetes.io/part-of: ard
    app.kubernetes.io/instance: devstack-a
    ard.openstack.org/deployment: devstack-a
    ard.openstack.org/provider: kubevirt
    ard.openstack.org/node: controller
    ard.node/name: controller
spec:
  running: true
  instancetype:
    kind: VirtualMachineInstancetype
    name: devstack-8c16g
  preference:
    kind: VirtualMachinePreference
    name: devstack
  template:
    metadata:
      labels:
        app.kubernetes.io/part-of: ard
        app.kubernetes.io/instance: devstack-a
        ard.openstack.org/deployment: devstack-a
        ard.openstack.org/provider: kubevirt
        ard.openstack.org/node: controller
        ard.node/name: controller
    spec:
      domain:
        devices:
          interfaces:
            - name: default
              masquerade: {}
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          persistentVolumeClaim:
            claimName: controller-rootdisk
        - name: cloudinitdisk
          cloudInitNoCloud:
            userData: |
              #cloud-config
              hostname: controller
              users:
                - name: stack
                  shell: /bin/bash
                  sudo: ALL=(ALL) NOPASSWD:ALL
                  ssh_authorized_keys:
                    - ssh-ed25519 ...
```

All-in-one and controller nodes use `devstack-8c16g`; compute nodes in a multinode topology use `devstack-8c8g`; all DevStack VMs use `VirtualMachinePreference/devstack` unless explicitly overridden.

### 11.7 Initial KubeVirt networking decision: pod network / masquerade

The first KubeVirt implementation should use the default pod network with masquerade binding.

Benefits:

- no Multus prerequisite
- works on more OpenShift Virtualization clusters
- simpler RBAC and cluster setup
- no dependency on provider-specific L2 network attachments
- sufficient for initial single-node and many multinode control-plane tests

Tradeoffs:

- VM IPs may not be stable in the same way as libvirt static IPs
- direct SSH needs an exposure mechanism
- traffic between VMs traverses the pod network path
- not a true shared L2 segment between VMs
- floating IP/provider network testing is limited unless additional routing is configured

### 11.8 SSH exposure for masquerade mode

With masquerade networking, the provider must expose SSH to Ansible.

Initial modes:

#### NodePort

Create one Service per VM:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: controller-ssh
  namespace: ard-devstack
spec:
  type: NodePort
  selector:
    ard.node/name: controller
  ports:
    - name: ssh
      protocol: TCP
      port: 22
      targetPort: 22
```

Inventory then uses:

```yaml
ansible_host: <selected cluster node address>
ansible_port: <allocated nodeport>
```

#### LoadBalancer

If the cluster supports LoadBalancer Services, expose each VM SSH through a LoadBalancer.

Inventory then uses:

```yaml
ansible_host: <service loadbalancer ingress ip or hostname>
ansible_port: 22
```

#### Port-forward

Useful for local development, but less suitable for long-running unattended automation.

Inventory uses local forwarded ports:

```yaml
ansible_host: 127.0.0.1
ansible_port: <local forwarded port>
```

#### Bastion

Future mode. A bastion pod or VM can provide a stable SSH jump host into the namespace.

Inventory uses:

```yaml
ansible_ssh_common_args: "-o ProxyJump=..."
```

### 11.9 KubeVirt inventory model

In masquerade mode, distinguish between:

1. the address Ansible uses to SSH into the VM; and
2. the address DevStack should use inside the VM for service and tunnel traffic.

Provider inventory should support both.

Example:

```yaml
controller:
  ansible_host: 192.0.2.25
  ansible_port: 32022
  ansible_user: stack
  ard_node_internal_ip: 10.0.2.2
  nodepool:
    private_ipv4: 10.0.2.2
    public_ipv4: 10.0.2.2
```

However, `10.0.2.2` is illustrative only. The provider must discover or configure the VM-internal IP used for node-to-node communication.

Potential approaches:

1. Query VM status interfaces from KubeVirt.
2. Use QEMU guest agent if available.
3. Use cloud-init to configure a known internal address where supported.
4. Use Ansible fact gathering after SSH connects and set `nodepool.private_ipv4` from the VM's default interface.

Initial recommendation:

- Use SSH exposure only for Ansible connectivity.
- After SSH works, gather facts inside the VM.
- Set `nodepool.private_ipv4` to the VM's default IPv4 address as seen inside the guest.
- Use those `nodepool` addresses for DevStack `HOST_IP`, `SERVICE_HOST`, and tunnel endpoints.

### 11.10 Multinode DevStack on KubeVirt with masquerade

The initial KubeVirt multinode design assumes the VM management/default IP path is sufficient for control-plane and overlay traffic.

For DevStack multinode:

- controller and computes communicate over their guest default interfaces
- DevStack config sets `HOST_IP` and `SERVICE_HOST` from `nodepool.private_ipv4`
- Neutron/OVN/OVS tenant networking uses tunnels where needed
- VXLAN tunnel endpoints use the VM management/default IPs

This avoids requiring Multus or a shared L2 provider network in the cluster.

Expected DevStack implications:

```yaml
HOST_IP: "{{ hostvars[inventory_hostname]['nodepool']['private_ipv4'] }}"
SERVICE_HOST: "{{ hostvars[groups['controller'][0]]['nodepool']['private_ipv4'] }}"
TUNNEL_ENDPOINT_IP: "{{ hostvars[inventory_hostname]['nodepool']['private_ipv4'] }}"
```

If using ML2/OVS with Linux bridge or VXLAN tunnels, ARD should ensure local.conf selects a tunnel-based tenant network mode rather than relying on external L2 adjacency.

Example intent:

```ini
ENABLE_TENANT_TUNNELS=True
ENABLE_TENANT_VLANS=False
Q_ML2_TENANT_NETWORK_TYPE=vxlan
```

The exact options depend on the selected Neutron backend and DevStack branch.

### 11.11 Deferred KubeVirt networking modes

Do not require these initially:

- Multus bridge networks
- SR-IOV networks
- dedicated L2 provider networks
- direct floating-IP reachability from outside the cluster

These can be added later as optional modes:

```yaml
ard_kubevirt_network_mode: multus
ard_kubevirt_network_attachment: ard-l2
```

## 12. Provider-neutral Profiles

Profiles are interpreted differently by libvirt and KubeVirt.

### 12.1 `ssh`

Provider must ensure:

- stack user exists
- SSH key is installed
- Ansible can connect
- Python is available for Ansible

### 12.2 `nested_virt`

Libvirt:

- check host nested virtualization
- set CPU mode, usually host-passthrough

KubeVirt:

- check cluster supports nested virtualization for VMs
- set required VM CPU/model/features if needed
- if unavailable, allow scenario to fall back to QEMU by setting DevStack `LIBVIRT_TYPE=qemu`

### 12.3 `ovn` / `ovs`

Provider does not configure Neutron directly. It only ensures the VM can support the requested DevStack configuration.

Libvirt:

- normal VM kernel/module behavior

KubeVirt:

- verify guest OS image can load/use required userspace packages
- avoid relying on external L2 adjacency in initial masquerade mode

### 12.4 `storage_lvm`

VM providers are safer for Cinder LVM than privileged containers because LVM/device state is isolated inside the guest.

Provider may add an extra disk per node:

```yaml
extra_disks:
  - name: cinder
    size_gb: 20
```

### 12.5 `ceph`

Ceph can be added as a higher-level DevStack plugin profile. Provider-specific work is mostly CPU/memory/disk sizing and optional extra disks.

## 13. Make Targets

Make should call provider-neutral playbooks.

Example:

```make
ARD_PROVIDER ?= libvirt
ARD_INVENTORY ?= localhost,
ARD_DEPLOYMENT ?= default
ARD_DEPLOYMENTS_DIR ?= deployments
ARD_DEPLOYMENT_DIR ?= $(ARD_DEPLOYMENTS_DIR)/$(ARD_DEPLOYMENT)
ARD_KUBEVIRT_NAMESPACE ?= ard-devstack
ARD_EXTRA_VARS ?= ard_provider=$(ARD_PROVIDER) ard_deployment_dir=$(ARD_DEPLOYMENT_DIR) ard_kubevirt_namespace=$(ARD_KUBEVIRT_NAMESPACE)

.PHONY: render
render:
	ansible-playbook -i $(ARD_INVENTORY) ansible/playbooks/ard-render.yaml \
		-e $(ARD_EXTRA_VARS)

.PHONY: apply
apply:
	ansible-playbook -i $(ARD_INVENTORY) ansible/playbooks/ard-apply.yaml \
		-e ard_deployment_dir=$(ARD_DEPLOYMENT_DIR)

.PHONY: create
create: apply

.PHONY: deploy
deploy:
	ansible-playbook -i $(ARD_INVENTORY) ansible/playbooks/ard-deploy-devstack.yaml \
		-e ard_deployment_dir=$(ARD_DEPLOYMENT_DIR)

.PHONY: verify
verify:
	ansible-playbook -i $(ARD_INVENTORY) ansible/playbooks/ard-verify.yaml \
		-e ard_deployment_dir=$(ARD_DEPLOYMENT_DIR)

.PHONY: destroy
destroy:
	ansible-playbook -i $(ARD_INVENTORY) ansible/playbooks/ard-destroy.yaml \
		-e ard_deployment_dir=$(ARD_DEPLOYMENT_DIR)

.PHONY: cleanup
cleanup:
	ansible-playbook -i $(ARD_INVENTORY) ansible/playbooks/ard-cleanup.yaml \
		-e ard_deployment_dir=$(ARD_DEPLOYMENT_DIR)

.PHONY: site
site:
	ansible-playbook -i $(ARD_INVENTORY) ansible/playbooks/ard-site.yaml \
		-e $(ARD_EXTRA_VARS)

.PHONY: kubevirt-resources
kubevirt-resources:
	oc apply -n $(ARD_KUBEVIRT_NAMESPACE) \
		-f ansible/files/kubevirt/devstack-instancetype-preference.yaml
```

Usage:

```bash
make render ARD_PROVIDER=kubevirt ARD_DEPLOYMENT=devstack-a
vi deployments/devstack-a/devstack/controller.yaml
vi deployments/devstack-a/devstack/nodes/compute1.yaml
make apply ARD_DEPLOYMENT=devstack-a
make deploy ARD_DEPLOYMENT=devstack-a
make destroy ARD_DEPLOYMENT=devstack-a
make cleanup ARD_DEPLOYMENT=devstack-a

make site ARD_PROVIDER=libvirt ARD_DEPLOYMENT=devstack-libvirt-a
make site ARD_PROVIDER=kubevirt ARD_DEPLOYMENT=devstack-kubevirt-a
make kubevirt-resources ARD_KUBEVIRT_NAMESPACE=ard-devstack
```

The KubeVirt provider should use `VirtualMachineInstancetype` and `VirtualMachinePreference` resources if they already exist. It should not create them by default. `make kubevirt-resources` is the explicit setup path to create or update the repo-carried defaults in the target namespace. An Ansible equivalent, `ard-kubevirt-ensure-resources.yaml`, can provide the same behavior for non-Make workflows.

## 14. Molecule Integration

Molecule should use ansible-native or delegated mode and call the same provider-neutral playbooks. Molecule should not own provider-specific VM creation logic. It should be a workflow runner and verifier.

To avoid defining topology and node names in multiple places, top-level Molecule scenarios should put ARD intent inline under `provisioner.ard` in `molecule.yml`. Molecule `platforms` are optional and should be omitted for these scenarios; ARD render presets generate the node list and provider inventory.

Example scenario structure:

```text
molecule/libvirt-multinode/
  molecule.yml              # includes provisioner.ard
  create.yml                # reads provisioner.ard, renders, applies
  converge.yml
  verify.yml
  destroy.yml
  deployment/               # generated/ignored
```

Example `molecule.yml` fragment:

```yaml
provisioner:
  name: ansible
  ard:
    provider: libvirt
    provider_profile: local-libvirt
    target_branch: master
    topology: one-controller-two-compute
    service_profiles:
      - devstack
      - ovn
      - tempest
    libvirt:
      network_cidr: 192.168.99.0/24
```

`create.yml` reads `molecule.yml`, writes generated render variables under the ignored deployment directory, calls `ard-render.yaml`, and then calls `ard-apply.yaml`. The same pattern applies to KubeVirt once that provider is implemented.

## 15. Zuul Integration

Zuul jobs should be able to call the same playbooks.

Important rule: do not assume dynamic inventory created in one Zuul phase persists into another phase.

Preferred patterns:

### 15.1 Create and deploy in one run playbook

```yaml
- name: Create provider VMs
  hosts: localhost
  roles:
    - ard_provider_preflight
    - ard_provider_image
    - ard_provider_network
    - ard_provider_node
    - ard_provider_inventory

- name: Deploy DevStack
  import_playbook: ansible/deploy_multinode_devstack.yaml
```

### 15.2 Pre-run creates, run re-discovers

- pre-run creates VMs
- run re-discovers VMs and calls `ard_provider_inventory`
- run deploys DevStack
- post-run re-discovers or collects logs via provider APIs

For KubeVirt, post-run log collection should work from the OpenShift API even if SSH fails.

## 16. Phased Implementation Plan

### Phase 0: Rename the design focus

- Treat `ARD_OCI_DESIGN.md` as deferred container-provider design.
- Add this provider-focused design.
- Decide provider-neutral variable names.

### Phase 1: Provider-neutral playbooks, dispatch roles, and upstream role refresh

- Refresh git submodules to current upstream master before validating the new provider flow:
  - `submodules/devstack`
  - `submodules/zuul-jobs`
  - `submodules/openstack-zuul-jobs`
- Re-check that ARD's `devstack_controller` and `devstack_compute` roles still call the current upstream `write-devstack-local-conf` and `run-devstack` roles with compatible variable names.
- Add `ard-create.yaml`.
- Add `ard-deploy-devstack.yaml`.
- Add `ard-destroy.yaml`.
- Add dispatcher roles:
  - `ard_provider_preflight`
  - `ard_provider_image`
  - `ard_provider_network`
  - `ard_provider_node`
  - `ard_provider_inventory`
  - `ard_provider_destroy`

### Phase 2: Libvirt single-node

- Create one controller VM.
- Bootstrap stack user via cloud-init.
- Verify SSH and Ansible fact gathering.
- Add inventory facts matching current ARD expectations.

### Phase 3: Libvirt multinode

- Create controller + compute1.
- Then controller + compute1 + compute2.
- Match current Vagrant scenario groups.
- Run existing `deploy_multinode_devstack.yaml`.

### Phase 4: Molecule libvirt scenario without Vagrant

- Add `molecule/libvirt-multinode`.
- Use provider playbooks for create/converge/destroy.
- Remove Vagrant from that path.

### Phase 5: KubeVirt single-node with masquerade

- Preflight OpenShift Virtualization access.
- Import or reference cloud image.
- Create one controller VM.
- Expose SSH through NodePort or chosen access mode.
- Gather facts inside the VM.
- Run a minimal DevStack deployment.

### Phase 6: KubeVirt multinode with masquerade

- Create controller + compute VM.
- Use guest default IPs as `nodepool.private_ipv4`.
- Configure DevStack for tunnel-based tenant networking when needed.
- Validate controller/compute communication over the pod-network path.

### Phase 7: Zuul provider jobs

- Add experimental jobs for libvirt and/or KubeVirt provider flows.
- Ensure post-run log collection works after partial failure.

### Phase 8: Advanced storage and networking profiles

- Extra disks for Cinder LVM.
- Ceph-capable sizing profiles.
- Optional KubeVirt Multus mode if needed later.

## 17. Risks and Open Questions

### 17.1 KubeVirt masquerade IP discovery

The provider must distinguish SSH endpoint from guest internal IP. Initial implementation should gather facts over SSH and set `nodepool.private_ipv4` from inside the guest.

### 17.2 KubeVirt SSH exposure

NodePort may not be available or allowed on all clusters. The provider should support multiple access modes, but start with one working mode.

### 17.3 Nested virtualization in KubeVirt

Nova KVM inside OpenShift Virtualization VMs depends on cluster support. Scenarios should be able to fall back to QEMU when nested virtualization is unavailable.

### 17.4 Multinode overlay over pod network

VXLAN or other tunnel traffic between VMs must work over the pod-network path. This should be validated early.

### 17.5 Provider-neutral static addressing

Libvirt can easily provide static management IPs. KubeVirt masquerade mode may require discovery rather than static assignment.

### 17.6 Log collection

Provider log collection should work without relying on a successful DevStack deployment or even working SSH.

### 17.7 Existing ARD assumptions

Some ARD roles may assume VM-like network behavior from Vagrant/libvirt. These should be adjusted only where necessary and kept provider-neutral.

### 17.8 Stale submodules and upstream role drift

ARD depends on git submodules for DevStack and Zuul/OpenStack Zuul job roles. These submodules may lag current upstream master. Refreshing them can change role defaults, job vars, or assumptions around `write-devstack-local-conf`, `run-devstack`, inventory, and Zuul-style variables. The provider prototype should update the submodules and validate that ARD's local DevStack wrapper roles still align with the current upstream role interfaces.

### 17.9 Libvirt prototype decisions

These decisions should be resolved before or during the first libvirt prototype:

- Debian 13 image variant: default to `debian-13-genericcloud-amd64.qcow2`; the `debian-13-nocloud-amd64.qcow2` image prompts for first-boot installation configuration in this workflow and is kept only as an alternate for future investigation.
- Image cache location: follow XDG cache conventions with `$XDG_CACHE_HOME/ard/images`, falling back to `~/.cache/ard/images`.
- Checksum policy: support checksums when configured, but do not require them for the first prototype unless reproducibility/security requirements demand it.
- Libvirt URI: prototype against `qemu:///system`; defer `qemu:///session` support. The first prototype assumes the invoking user has sufficient `libvirt`/`qemu` group access and should not use Ansible `become` by default.
- VM naming: use `ard-<deployment-name>-<inventory-name>` as the provider resource name, e.g. `ard-devstack-1-controller`, while keeping inventory hostnames as `controller`, `compute1`, etc.
- Destroy semantics: delete per-deployment overlays, seed ISOs, domains, and generated networks by default, but keep cached base images.
- Filesystem paths: store downloaded base images in XDG cache and libvirt per-deployment base copies, overlays, and seed ISOs in XDG state. The provider should not write to `/var/lib/libvirt/images` by default and should not silently sudo provider operations.
- Network default: use NAT `192.168.96.0/24` for the libvirt prototype.

## 18. Recommended Initial Defaults

For local work:

```yaml
ard_provider: libvirt
ard_default_image: debian-13
ard_default_controller_flavor: devstack-control
ard_default_compute_flavor: devstack-compute
ard_default_vm_preference: devstack
ard_default_topology: one-controller-one-compute
```

For remote OpenShift work:

```yaml
ard_provider: kubevirt
ard_kubevirt_network_mode: masquerade
ard_kubevirt_ssh_access: nodeport
ard_kubevirt_storage_class: null
ard_kubevirt_default_image: debian-13
ard_kubevirt_default_controller_flavor: devstack-control
ard_kubevirt_default_compute_flavor: devstack-compute
ard_kubevirt_default_preference: devstack
ard_kubevirt_ensure_instancetype_resources: false
ard_default_topology: one-controller-one-compute
```

For KubeVirt multinode DevStack, express local.conf inputs through the existing controller/compute variables, for example in `deployments/<name>/devstack/group_vars/controller.yaml` and `deployments/<name>/devstack/group_vars/compute.yaml`:

```yaml
controller_localrc_extra:
  ENABLE_TENANT_TUNNELS: true
  ENABLE_TENANT_VLANS: false

compute_localrc_extra:
  ENABLE_TENANT_TUNNELS: true
  ENABLE_TENANT_VLANS: false
```

The exact DevStack networking keys should be validated against the selected Neutron backend and branch.

## 19. Summary

Short-term ARD provider work should focus on VM providers:

1. libvirt to replace the current Molecule/Vagrant/libvirt workflow; and
2. KubeVirt/OpenShift Virtualization to use a remote OpenShift cluster as an additional VM host.

The first KubeVirt implementation should use pod-network/masquerade mode and avoid requiring Multus. For multinode DevStack, ARD should rely on the guest default network path and DevStack-managed tunnel overlays such as VXLAN when tenant or inter-node overlay networking is required.

The provider layer creates VMs and inventory. Existing ARD DevStack roles continue to deploy OpenStack. This keeps the provisioning model replaceable without making DevStack deployment provider-specific.
