# ARD From Scratch: Developer Guide

This guide explains how ARD is organized, how a local ARD deployment is built from scratch, and how contributors should reason about the provider, inventory, and DevStack layers. It is written for readers who know Linux, Ansible, and virtualization in general, but who may be new to ARD's local libvirt provider or to the existing DevStack/Zuul role conventions used by this repository.

ARD is a local development and test harness for VM-backed DevStack deployments. The main workflow uses Ansible provider playbooks to provision VMs, generate an ARD/Zuul-like inventory, and then run the existing DevStack deployment roles inside those VMs. The current implemented local provider is libvirt. KubeVirt/OpenShift Virtualization is design work for a later phase.

The intended direction is similar to a project-specific reference manual: concepts are introduced before they are used, the deployment flow is explained from scratch, and the ARD-specific roles, presets, generated files, and local state paths are documented as part of the system rather than treated as incidental YAML.

This guide is not a replacement for the Ansible documentation, libvirt documentation, DevStack documentation, or OpenStack/Zuul role documentation. It focuses on the subset needed to understand how ARD connects those systems together.

## How to read this guide

The document is both a learning path and a reference. New contributors should read Parts I through IV first, then skim Part V before changing provider roles or rendered deployment data. Parts VI through XI are more reference oriented and can be read as needed.

```text
Part I    Orientation and mental model
Part II   Development host preparation and quick starts
Part III  Ansible, Make, and repository layout
Part IV   Full deployment-from-scratch walkthrough
Part V    Render presets, deployment workspaces, and inventory
Part VI   Provider role reference
Part VII  DevStack deployment layer reference
Part VIII Molecule, validation, and test strategy
Part IX   Maintenance workflows
Part X    Troubleshooting
Part XI   Quick reference
```

Headings are intentionally not manually numbered. Use the Markdown outline or search for the referenced heading name when following cross-references.

A practical first pass for new contributors is:

1. Read `README.md` for the public quick start and workflow summary.
2. Run `./bootstrap-repo.sh` on a suitable Linux host.
3. Read the top-level `Makefile` from top to bottom.
4. Read the provider playbooks under `ansible/playbooks/`.
5. Read `ansible/roles/ard_provider_render/tasks/main.yml` and `ansible/roles/ard_provider_render/templates/nodes.yaml.j2`.
6. Read the preset files under `ansible/roles/ard_provider_common/files/presets/`.
7. Run `make render ARD_DEPLOYMENT=devstack-a` and inspect `deployments/devstack-a/`.
8. Run `make apply ARD_DEPLOYMENT=devstack-a` on a libvirt-capable host and inspect `inventory.yaml`, `provider-state.yaml`, and `rendered/libvirt/`.
9. Read `ansible/roles/ard_libvirt_*` when debugging provisioning.
10. Read `ansible/deploy_multinode_devstack.yaml` and the `devstack_*` roles when debugging DevStack itself.

Existing focused docs remain useful as source material:

```text
README.md                                      public overview, quick start, workflow, presets, troubleshooting
ARD_PROVIDER_DESIGN.md                         provider framework design intent and future-provider context
ansible/roles/*/README.md                      role-level notes for older and focused roles
molecule/*/molecule.yml                        full deployment scenario definitions
ansible/playbooks/ard-molecule-create.yaml      shared Molecule create/render/apply seam
ansible/roles/*/molecule/*/molecule.yml        role-level Molecule scenario definitions
examples/vdpa/                                 example vDPA inventory/configuration
```

Prefer this guide for current contributor orientation. Use focused docs for local detail, then verify commands against current playbooks and roles before treating them as canonical.

# Part I - Orientation

## What ARD is

ARD provides local automation for creating VM-backed DevStack environments. A typical ARD run creates one or more VMs, configures SSH access, writes an Ansible inventory that looks like the inventory expected by the existing DevStack/Zuul roles, and then deploys DevStack across the generated nodes.

The current primary development target is a local libvirt deployment using `qemu:///system`. A rendered deployment can be all-in-one, one controller plus one compute, or one controller plus two computes. The provider framework is written to keep provider-specific logic isolated so that future providers can create equivalent inventories without changing the DevStack roles.

ARD is useful for:

- testing DevStack multinode changes locally,
- testing OpenStack service combinations such as OVN, Tempest, Ceph, or vDPA-related setups,
- validating provider/inventory behavior outside of Zuul,
- reproducing CI-like VM topologies on a developer workstation,
- iterating on Ansible roles that configure DevStack controllers and computes.

ARD is not:

- a production OpenStack deployment tool,
- a replacement for DevStack,
- a replacement for Zuul,
- currently a general multi-provider provisioning framework in implementation, even though the design keeps that direction open.

## The core mental model

The most important idea is that ARD has two major phases:

1. create provider nodes and inventory,
2. use that inventory to run the existing DevStack deployment flow.

The high-level flow is:

```text
Make / Molecule / developer command
        |
        v
ARD provider playbooks
        |
        v
provider common + dispatcher roles
        |
        v
libvirt provider roles
        |
        v
VMs with SSH access
        |
        v
generated Ansible inventory and provider state
        |
        v
ARD DevStack configuration loader
        |
        v
existing DevStack/Zuul-style deployment roles
        |
        v
DevStack running inside VMs
```

The provider's job ends when:

1. VMs exist,
2. the management network is usable,
3. SSH works,
4. cloud-init has completed,
5. `inventory.yaml` has the expected logical names, groups, host variables, and nodepool-style facts.

After that, the DevStack roles should not need to know whether nodes came from libvirt, KubeVirt, or a future provider.

## Source of truth versus generated state

ARD deliberately separates persistent intent from generated deployment state.

Persistent source of truth normally lives in:

```text
Makefile
bootstrap-repo.sh
bindep.txt
pyproject.toml
uv.lock
ansible.cfg
ansible/playbooks/
ansible/roles/
ansible/roles/ard_provider_common/files/presets/
ansible/roles/ard_provider_render/templates/
molecule/
examples/
```

Generated or local state normally lives in:

```text
deployments/<deployment-name>/deployment.yaml
deployments/<deployment-name>/nodes.yaml
deployments/<deployment-name>/devstack/common.yaml
deployments/<deployment-name>/devstack/group_vars/*.yaml
deployments/<deployment-name>/inventory.yaml
deployments/<deployment-name>/provider-state.yaml
deployments/<deployment-name>/rendered/
deployments/<deployment-name>/logs/
$XDG_CACHE_HOME/ard/images or ~/.cache/ard/images
$XDG_STATE_HOME/ard/libvirt/images/<deployment-name> or ~/.local/state/ard/libvirt/images/<deployment-name>
```

`render` may overwrite `deployment.yaml`, `nodes.yaml`, and generated `devstack/*.yaml` files. Keep durable custom intent in a render file or deployment-local overlay such as `overrides/render.yaml`.

## Terminology used in this guide

`ARD`  
: This repository and its Ansible/Make/Molecule workflow for VM-backed DevStack development.

`provider`  
: The implementation that creates nodes and inventory. The implemented provider is currently `libvirt`.

`provider dispatcher role`  
: A role named like `ard_provider_node` that loads deployment data and includes a provider-specific role such as `ard_libvirt_node`.

`deployment workspace`  
: A directory under `deployments/<name>/` or a Molecule scenario deployment directory. It contains rendered inputs, generated inventory, provider state, rendered libvirt artifacts, and logs.

`render intent`  
: The small user-supplied variable set that selects provider, topology, branch, service profiles, network CIDR, and overrides. It can be passed through Make variables, `ARD_RENDER_FILE`, or deployment-local overlays.

`preset`  
: A reusable YAML definition for topologies, services, branches, networks, node types, or provider profiles.

`topology`  
: A node layout preset such as `all-in-one`, `one-controller-one-compute`, or `one-controller-two-compute`.

`service profile`  
: A preset such as `devstack`, `ovn`, `tempest`, or `ceph` that contributes node profiles and DevStack variables.

`node type`  
: A preset such as `controller` or `compute` that contributes groups, default profiles, and default flavor.

`management network`  
: The network used for Ansible SSH connectivity and `nodepool.private_ipv4`/`public_ipv4` values. The default is `ard-mgmt`.

`provider state`  
: The generated file that records provider resource names, network names, disk paths, seed ISO paths, console logs, IPs, and MAC addresses for inspection and cleanup.

`DevStack layer`  
: The playbooks and roles that configure the VMs and run DevStack after the provider has created nodes.

With the project overview and vocabulary in place, Part II covers development host setup and quick-start commands.

# Part II - Development host preparation and quick starts

## Development host assumptions

The local provider expects a Linux host capable of running libvirt/KVM VMs through `qemu:///system`. You need enough CPU, memory, and disk for the selected topology. The default one-controller-one-compute topology uses the `devstack-control` and `devstack-compute` flavors; those are intentionally large enough for DevStack rather than tiny smoke-test VMs.

The dependency model has three layers:

1. minimal system tools needed to install Python tooling,
2. bindep-managed operating-system packages,
3. Python dependencies managed by `uv`.

`bootstrap-repo.sh` handles the normal setup path. It detects `apt` or `dnf`, installs minimal Python/curl dependencies, ensures `uv`, installs packages reported by bindep, runs `uv sync`, updates submodules, and checks local libvirt commands.

Important host commands include:

```text
virsh
qemu-img
cloud-localds
setfacl
rsync
git
podman, for role-level Molecule scenarios that use containers
```

Your user normally needs permission to use libvirt. If `qemu:///system` is not reachable, check group membership, libvirt daemon state, and host virtualization support before debugging ARD roles.

## Bootstrap the repository

From a fresh checkout:

```bash
./bootstrap-repo.sh
```

Useful bootstrap toggles:

```bash
DRY_RUN=1 ./bootstrap-repo.sh
SKIP_PACKAGES=1 ./bootstrap-repo.sh
SKIP_UV_INSTALL=1 ./bootstrap-repo.sh
SKIP_SUBMODULES=1 ./bootstrap-repo.sh
```

Use the skip flags only when you know that layer is already handled by your environment.

## Quick start: render only

A render-only run is the safest first step because it does not create VMs:

```bash
make render ARD_DEPLOYMENT=devstack-a
```

Inspect:

```bash
find deployments/devstack-a -maxdepth 4 -type f | sort
cat deployments/devstack-a/deployment.yaml
cat deployments/devstack-a/nodes.yaml
cat deployments/devstack-a/devstack/common.yaml
cat deployments/devstack-a/devstack/group_vars/controller.yaml
cat deployments/devstack-a/devstack/group_vars/compute.yaml
```

This teaches the core data model without requiring libvirt to work.

## Quick start: create provider nodes

On a libvirt-capable host:

```bash
make apply ARD_DEPLOYMENT=devstack-a
make ping ARD_DEPLOYMENT=devstack-a
```

`apply` creates provider resources, writes `inventory.yaml`, adds the generated hosts to the active inventory, waits for SSH, and waits for cloud-init completion.

Inspect:

```bash
cat deployments/devstack-a/inventory.yaml
cat deployments/devstack-a/provider-state.yaml
find deployments/devstack-a/rendered -maxdepth 4 -type f | sort
```

To SSH to a node:

```bash
make ssh ARD_DEPLOYMENT=devstack-a ARD_NODE=controller
make ssh-print ARD_DEPLOYMENT=devstack-a ARD_NODE=compute-1
```

The `ssh-print` form is useful when you want to copy the command or inspect the generated SSH options.

## Quick start: deploy and verify DevStack

After `apply` and `ping` succeed:

```bash
make deploy ARD_DEPLOYMENT=devstack-a
make verify ARD_DEPLOYMENT=devstack-a
```

`deploy` runs the DevStack deployment playbook against the generated inventory. `verify` checks inventory presence, pings all nodes, verifies that `/opt/repos/devstack` exists on the controller, and can optionally run a Tempest smoke test when requested.

## Quick start: destroy and clean up

To destroy provider resources while keeping generated artifacts for inspection:

```bash
make destroy ARD_DEPLOYMENT=devstack-a
```

To destroy provider resources and remove generated runtime artifacts:

```bash
make destroy-clean-generated ARD_DEPLOYMENT=devstack-a
```

To remove generated inventory, provider state, and rendered artifacts without touching provider resources:

```bash
make clean-generated ARD_DEPLOYMENT=devstack-a
```

To remove the entire local deployment workspace:

```bash
make cleanup ARD_DEPLOYMENT=devstack-a
```

Use `destroy` first when VMs or libvirt networks still exist. Use `cleanup` only when you no longer need the workspace.

## Quick start: full rebuild

The default target performs a full local rebuild workflow:

```bash
make ARD_DEPLOYMENT=devstack-a
```

It runs best-effort destroy/cleanup steps, then `render`, `apply`, `ping`, `deploy`, and `verify`. This is convenient when the host is already prepared and failures from prior runs should be cleared. It is not the best first command for learning because it performs every stage at once.

# Part III - Ansible, Make, and repository layout

## Top-level repository map

High-level source layout:

```text
.
├── README.md                         public quick start and workflow documentation
├── developer-guide.md                this contributor guide
├── ARD_PROVIDER_DESIGN.md            provider framework design plan
├── Makefile                          primary local command interface
├── bootstrap-repo.sh                 host/repository bootstrap helper
├── bindep.txt                        OS package dependency list
├── pyproject.toml                    Python dependency metadata for uv
├── uv.lock                           locked Python environment
├── ansible.cfg                       role path and Ansible defaults
├── ansible/
│   ├── playbooks/                    ARD provider and workflow playbooks
│   ├── roles/                        ARD provider, libvirt, DevStack, and helper roles
│   ├── deploy_multinode_devstack.yaml
│   ├── devstack_common.yaml
│   ├── devstack_controller.yaml
│   ├── devstack_compute.yaml
│   └── vdpa.yaml
├── molecule/                         full ARD/libvirt-backed scenarios
├── examples/                         focused example inputs
├── scripts/                          small developer helpers
├── deployments/                      local deployment workspaces, mostly generated
├── submodules/                       DevStack and Zuul role submodules
└── okd/                              older/future OpenShift-related scratch area
```

## Makefile as command interface

Most contributor commands should go through the top-level `Makefile`. It centralizes defaults and ensures the same playbooks are used consistently.

Important variables:

```text
ARD_PROVIDER          provider, currently libvirt
ARD_DEPLOYMENT        deployment name, default devstack-1
ARD_DEPLOYMENTS_DIR   parent directory for deployment workspaces
ARD_DEPLOYMENT_DIR    full deployment workspace path
ARD_TOPOLOGY          topology preset
ARD_TARGET_BRANCH     DevStack branch preset/branch string
ARD_SERVICES          comma-separated service profile list
ARD_PROVIDER_PROFILE  provider profile preset
ARD_IMAGE             optional image key override
ARD_NETWORK_CIDR      management network CIDR
ARD_RENDER_FILE       optional render intent file
ARD_NODE              node selected by make ssh
ARD_SSH_PRINT         print SSH command instead of executing it
ARD_SSH_ARGS          extra arguments passed to ssh
ARD_EXTRA_VARS        extra Ansible variables appended to provider commands
```

Common targets:

```text
render                  generate deployment.yaml, nodes.yaml, and DevStack vars
apply                   create provider resources and inventory
ping                    run Ansible ping against generated inventory
ssh                     SSH to a generated inventory host
ssh-print               print the generated SSH command
deploy                  deploy DevStack
verify                  run post-deploy checks
destroy                 remove provider resources
clean-generated         remove inventory/state/rendered artifacts
cleanup                 delete the deployment workspace
site                    render, apply, deploy, verify
molecule-test           run role-level Molecule tests
molecule-role-<role>    run one role-level Molecule scenario
```

The default target is intentionally broad. Prefer individual targets while developing a specific layer.

## Ansible configuration and submodules

`ansible.cfg` sets the role search path to:

```text
ansible/roles
submodules/devstack/roles
submodules/zuul-jobs/roles
submodules/openstack-zuul-jobs/roles
```

This matters because some role names referenced by ARD playbooks are local, while others come from upstream DevStack or Zuul job repositories. If a role is not found, verify that submodules were initialized and that Ansible is running with the repository `ansible.cfg`.

The submodules are:

```text
submodules/devstack
submodules/zuul-jobs
submodules/openstack-zuul-jobs
```

Run this if they are missing:

```bash
git submodule update --init --recursive
```

## Python environment

ARD uses `uv` for the Python environment. The project metadata declares `ansible-core`, `passlib`, `netaddr`, `molecule`, and Molecule Podman plugins. The repository is not packaged as an installable Python package; `tool.uv.package = false` keeps it as a tooling environment.

Use:

```bash
uv sync
uv run ansible --version
uv run ansible-playbook --version
uv run molecule --version
```

Prefer `uv run ...` in documentation and scripts unless you intentionally rely on an activated virtual environment.

# Part IV - Full deployment-from-scratch walkthrough

This section walks through what happens when you run:

```bash
make render apply ping deploy verify ARD_DEPLOYMENT=devstack-a
```

The exact Make invocation above is shorthand for the individual targets. In practice, run them one at a time when debugging.

## Stage 1: Make variable resolution

The Makefile resolves defaults such as:

```text
ARD_PROVIDER=libvirt
ARD_DEPLOYMENT=devstack-1
ARD_TOPOLOGY=one-controller-one-compute
ARD_TARGET_BRANCH=master
ARD_SERVICES=devstack,ovn,tempest
ARD_PROVIDER_PROFILE=local-libvirt
ARD_NETWORK_CIDR=192.168.96.0/24
```

It then converts command-line Make variables into Ansible extra vars. Render-specific values are passed to `ard-render.yaml`; deployment-stage values are passed to apply/deploy/verify/destroy/cleanup playbooks.

## Stage 2: render starts and loads intent

`ansible/playbooks/ard-render.yaml` runs on localhost and includes:

```text
ard_provider_common
ard_provider_render
```

The render role first establishes `ard_deployment_dir` and `ard_deployment_name`. It then looks for:

```text
<deployment-dir>/render.yaml
<deployment-dir>/overrides/render.yaml
```

If `ARD_RENDER_FILE` is provided through Make, it is passed as an extra vars file before the ordinary render variables. Render intent can therefore come from Make variables, a checked-in example file, a local deployment file, or an overlay.

## Stage 3: render loads presets

The render role loads these preset groups:

```text
topologies.yaml
branches.yaml
services.yaml
node-types.yaml
networks.yaml
provider-profiles.yaml
```

Then it validates the selected provider, topology, provider profile, service profiles, and network CIDR.

As of this guide, render validates `ard_provider == 'libvirt'`. If you are adding another provider, the render validation and provider-specific render output are among the first things that need to change.

## Stage 4: render composes services, branch, provider defaults, and networks

Service profiles are merged in the requested order. Profiles can contribute DevStack variables and node profiles. For example, the default service list `devstack,ovn,tempest` enables DevStack defaults, adds OVN node profile data, and includes Tempest-related configuration hooks.

Branch presets contribute DevStack branch defaults. Provider profile presets contribute image/flavor/preference defaults. Network presets define management and optional tenant networks.

The render role then composes:

```text
ard_render_services_config
ard_render_node_profiles
ard_render_branch_config
ard_render_provider_profile_config
ard_render_provider_defaults
ard_render_networks_config
```

## Stage 5: render normalizes nodes

The `nodes.yaml.j2` template turns topology pools and node type presets into concrete nodes.

For each pool, it derives:

```text
node name
hostname
provider resource name
groups
image
flavor
preference
attached networks
IP addresses where applicable
MAC addresses
profiles
```

For the default `one-controller-one-compute` topology, the logical nodes are:

```text
controller
compute-1
```

The controller is in groups such as `controller` and `switch`. The compute is in groups such as `compute`, `peers`, and `subnode`. These group names are part of the existing DevStack/Zuul role contract, so treat them carefully.

## Stage 6: render writes deployment files

The render role writes:

```text
deployments/<name>/deployment.yaml
deployments/<name>/nodes.yaml
deployments/<name>/devstack/common.yaml
deployments/<name>/devstack/group_vars/controller.yaml
deployments/<name>/devstack/group_vars/compute.yaml
```

It also ensures directories such as:

```text
deployments/<name>/devstack/group_vars
deployments/<name>/devstack/host_vars
deployments/<name>/rendered/libvirt
deployments/<name>/logs
```

At this point no VMs have been created.

## Stage 7: apply loads deployment data

`ansible/playbooks/ard-apply.yaml` runs on localhost, gathers facts, and includes:

```text
ard_provider_common
ard_provider_preflight
ard_provider_image
ard_provider_network
ard_provider_node
ard_provider_inventory
```

The provider dispatcher roles load `deployment.yaml` and `nodes.yaml`, then include the provider-specific roles. With `ard_provider: libvirt`, they call libvirt roles.

## Stage 8: apply performs preflight

The preflight layer exists to verify provider-specific requirements before expensive creation work. For libvirt, this is where provider prerequisites should be checked and normalized. When adding checks, keep them actionable: a contributor should know which missing command, daemon, permission, or variable caused the failure.

## Stage 9: apply prepares the base image

The libvirt image role selects the configured cloud image from `ard_images`, resolves the image cache directory, downloads the base image when needed, verifies it exists, ensures the per-deployment image directory exists, and grants libvirt access to the relevant paths.

By default, base images are cached under:

```text
$XDG_CACHE_HOME/ard/images
```

or:

```text
~/.cache/ard/images
```

Per-deployment disks and seed ISOs are placed under:

```text
$XDG_STATE_HOME/ard/libvirt/images/<deployment-name>
```

or:

```text
~/.local/state/ard/libvirt/images/<deployment-name>
```

## Stage 10: apply creates libvirt networks

The libvirt network role renders network XML under the deployment workspace, checks whether each libvirt network already exists, defines missing networks, starts them, and marks them autostart.

The default management network is a NAT network. Additional networks can be NAT or isolated depending on render configuration.

## Stage 11: apply creates VM nodes

For each rendered node, the libvirt node role:

1. resolves provider facts such as resource name, flavor, management IP, MAC, render directory, disk path, seed path, and console log path,
2. writes cloud-init `user-data`,
3. writes cloud-init `meta-data`,
4. writes cloud-init `network-config`,
5. builds a NoCloud seed ISO with `cloud-localds`,
6. copies the seed ISO into the libvirt image directory,
7. creates a qcow2 disk from the cached base image,
8. resizes the disk to the selected flavor size,
9. ensures a console log file exists,
10. grants libvirt access with ACLs,
11. renders domain XML,
12. defines the libvirt domain if missing,
13. starts the domain.

Cloud-init config creates a `stack` user, installs the ARD SSH public key, enables password auth as a fallback, installs basic packages, configures serial console logging, and restarts SSH.

## Stage 12: apply writes inventory and provider state

The libvirt inventory role writes:

```text
deployments/<name>/inventory.yaml
deployments/<name>/provider-state.yaml
```

The inventory uses logical names such as `controller` and `compute-1`, not libvirt domain names. It sets `ansible_host`, `ansible_user`, `ansible_private_key_file`, SSH common args, `nodepool.private_ipv4`, `nodepool.public_ipv4`, and minimal `zuul.executor` facts.

The provider state file records enough libvirt resource data to inspect or debug the deployment:

```text
provider
libvirt URI
management network
libvirt network names
domain names
IP and MAC addresses
overlay disk paths
seed ISO paths
console log paths
```

## Stage 13: apply waits for nodes

After local provider creation, `ard-apply.yaml` runs a second play against `ard_provider_nodes`. It waits for SSH/Ansible connectivity and then waits for cloud-init completion. This prevents `make apply` from returning before the generated inventory is actually usable.

## Stage 14: ping verifies connectivity

`make ping` runs:

```bash
uv run ansible -i <deployment-dir>/inventory.yaml all -m ansible.builtin.ping
```

This is a cheap sanity check that the generated inventory and SSH credentials work outside the apply playbook.

## Stage 15: deploy loads DevStack variables

`ard-deploy-devstack.yaml` first refreshes provider inventory and then runs `ard_devstack_config` on all hosts. That role loads:

```text
<deployment-dir>/devstack/common.yaml
<deployment-dir>/devstack/group_vars/<group>.yaml
<deployment-dir>/devstack/host_vars/<inventory-host>.yaml
```

This lets rendered DevStack defaults and user customizations become ordinary Ansible variables before the existing DevStack playbooks run.

## Stage 16: deploy runs multinode DevStack

`ard-deploy-devstack.yaml` imports `ansible/deploy_multinode_devstack.yaml`.

That playbook:

1. ensures local cache directories,
2. runs common DevStack preparation on all hosts,
3. optionally configures vDPA,
4. pushes apt/dnf/pip/git caches to targets,
5. deploys the controller,
6. exports nodepool/Zuul-style facts,
7. syncs controller data to subnodes,
8. optionally syncs Ceph config,
9. deploys computes,
10. runs DevStack host discovery,
11. pulls caches back for future runs.

When debugging DevStack failures, determine whether the failure happened before or after the provider boundary. Provider failures usually involve libvirt, cloud-init, SSH, images, disks, or inventory. DevStack failures usually involve package installation, git checkouts, local.conf rendering, service startup, or OpenStack-specific configuration.

## Stage 17: verify performs post-deploy checks

`make verify` runs `ard-verify.yaml`. It checks that generated inventory exists, pings all nodes, checks for `/opt/repos/devstack` on the controller, and optionally runs Tempest smoke when `ard_verify_tempest_smoke` is true.

# Part V - Render presets, deployment workspaces, and inventory

## Render input precedence

Render inputs can come from several places. The common sources are:

1. role defaults,
2. preset files,
3. render intent files,
4. deployment-local overlay files,
5. Make command-line variables,
6. explicit `ARD_EXTRA_VARS` or direct `ansible-playbook -e` values.

The exact Ansible variable precedence rules still apply. When debugging surprising values, print the rendered `deployment.yaml`, `nodes.yaml`, and DevStack group vars first. Those files show what the provider and DevStack layers will consume.

## Topology presets

Current built-in topology presets are:

```text
all-in-one
one-controller-one-compute
one-controller-two-compute
```

`all-in-one` creates only `controller`.

`one-controller-one-compute` creates:

```text
controller
compute-1
```

`one-controller-two-compute` creates:

```text
controller
compute-1
compute-2
```

Topology presets are composed from node pools. A singleton pool can provide an explicit node name. A counted pool can provide name and hostname formats such as `compute-{index}`.

If a topology says the controller does not run compute services, render disables `n-cpu` on the controller through controller group vars.

## Node type presets

Node types define group membership, default profiles, and default flavor.

The controller type contributes groups expected by the controller/switch side of the DevStack multinode flow. The compute type contributes groups expected by subnode/peer/compute flows.

Changing group names can break existing roles. If you need new groups, add them without removing compatibility groups unless you are deliberately changing the DevStack contract.

## Service profiles

Service profiles let a small render intent select related node profiles and DevStack variable sets.

Current service profiles are:

```text
devstack
ovn
tempest
ceph
```

The default service list is:

```text
devstack,ovn,tempest
```

A service profile can contribute:

```text
node_profiles
devstack.common
devstack.controller
devstack.compute
```

Use service profiles for reusable feature-level bundles. Use render overrides for one-off local experiments.

## Branch presets

Branch presets map an ARD target branch to DevStack variables and, when needed, provider defaults. The default branch is `master`. The `stable/2026.1` preset currently selects `stable/2026.1` and changes the default image to Ubuntu 24.04.

When adding a branch preset, document why any image or service default differs from master.

## Network presets

The default `ard-mgmt` network is NAT-backed and used for SSH/inventory. The built-in `tenant` network is isolated and opt-in. Isolated networks render without host-side IP, NAT, or DHCP, but VM interfaces still get deterministic MAC addresses and stable interface names.

`ard_management_network` selects which attached network is used for SSH and `nodepool` facts. The management network must be a NAT network with IP addresses.

## Provider profile presets

The default provider profile is `local-libvirt`. It selects:

```text
provider: libvirt
default image: debian-13
controller flavor: devstack-control
compute flavor: devstack-compute
VM preference: devstack
```

Provider profiles should describe reusable provider-level defaults, not one-off local deployment decisions.

## Render overrides

Use `ard_render_overrides` for recursive dictionary merges into provider defaults, topology, node pools, networks, and DevStack variables. Later dictionaries replace scalar and list values for the relevant section.

Use `ard_render_node_overrides` for per-node changes after the node is generated from topology and node type presets.

Example pattern:

```yaml
---
ard_provider: libvirt
ard_provider_profile: local-libvirt
ard_target_branch: master
ard_topology: one-controller-one-compute
ard_service_profiles:
  - devstack
  - ovn
  - tempest
ard_libvirt_network_cidr: 192.168.98.0/24

ard_render_overrides:
  provider_defaults:
    image: ubuntu-24.04
  node_pools:
    compute:
      count: 2
  devstack:
    common:
      enable_ceph: false

ard_render_node_overrides:
  compute-2:
    networks:
      ard-mgmt:
        ip: 192.168.98.50
```

Keep examples small. If an override becomes reusable, consider making it a preset.

## Inventory contract

Generated inventory must preserve the logical names and groups expected by the DevStack deployment layer. Inventory hostnames remain `controller`, `compute-1`, and `compute-2` even though provider resources are named with deployment-specific prefixes such as `ard-devstack-a-controller`.

Each generated host should include:

```text
ansible_host
ansible_user
ansible_private_key_file
ansible_ssh_common_args
ard_deployment_name
ard_provider_resource_name
nodepool.private_ipv4
nodepool.public_ipv4
zuul.executor.log_root
zuul.executor.work_root
```

Group membership is not just cosmetic. It determines which DevStack playbooks and roles run on each node.

# Part VI - Provider role reference

## Provider common

`ard_provider_common` supplies defaults shared across provider workflows. Its task file is intentionally a no-op so playbooks can include the role explicitly and get role defaults loaded before dispatcher roles run.

Important defaults include:

```text
ard_provider
ard_provider_profile
ard_topology
ard_target_branch
ard_service_profiles
ard_default_image
ard_default_controller_flavor
ard_default_compute_flavor
ard_management_network
ard_image_cache_dir
ard_libvirt_uri
ard_libvirt_pool
ard_libvirt_network_cidr
ard_libvirt_image_dir
ard_apply_wait_timeout
ard_images
ard_flavors
```

## Provider render

`ard_provider_render` is the highest-leverage role in the repository. It converts small human intent into concrete provider and DevStack inputs.

Responsibilities:

- load render intent and overlay files,
- load presets,
- normalize service profile lists,
- validate supported inputs,
- compose topology, service, branch, provider, and network configs,
- normalize nodes with the `nodes.yaml.j2` template,
- validate node uniqueness, IP uniqueness, MAC uniqueness, and management network correctness,
- compose DevStack common/controller/compute variables,
- write generated deployment files.

If render output is wrong, fix render before debugging lower provider layers.

## Provider preflight

`ard_provider_preflight` loads deployment and node variables, then dispatches to provider-specific preflight. Use this layer for checks that should fail fast before image downloads or VM creation.

Good preflight checks are:

- required host commands exist,
- provider connection is reachable,
- selected provider values are supported,
- required credentials or permissions are present,
- impossible topology/provider combinations are rejected early.

## Provider image

`ard_provider_image` dispatches to image handling for the selected provider. The libvirt implementation resolves the selected cloud image and ensures the cached base image is available.

When adding image support, decide whether image selection is deployment-wide or per-node. The current libvirt image role uses the deployment default image as the selected base image, while nodes can still carry image metadata from render. If you introduce true mixed-image deployments, audit this role carefully.

## Provider network

`ard_provider_network` dispatches to provider-specific network creation. The libvirt implementation renders one XML file per rendered network, defines missing networks, starts them, and marks them autostart.

NAT networks render `<forward mode='nat'/>`, a gateway IP, and static DHCP host entries for every node interface on that network that has an IP address. Isolated networks render without host-side IP, NAT, or DHCP. The libvirt network template also honors provider-specific details such as a `provider.libvirt.bridge_name` value if that value is present in the consumed deployment data, which is useful for specialized local experiments.

When changing network behavior, keep the management-network contract front and center. Ansible must be able to SSH to every node through the selected management network, and `ard_management_network` must continue to point at a NAT network with deterministic guest IPs. Extra networks should be additive: attach them to nodes through topology/pool/node overrides, generate stable MAC addresses, and avoid changing the logical inventory address unless the management network itself changes.

## Provider node

`ard_provider_node` dispatches to provider-specific node creation. The libvirt implementation loops through `ard_nodes` and includes `node.yml` per node.

For each node network, cloud-init matches the deterministic MAC address, assigns a stable interface name such as `eth0`, and configures a static address only when render produced one. Interfaces without an IP are explicitly marked optional with DHCP disabled, which is important for isolated tenant-style networks that guests may configure themselves later. The management network receives the default route and DNS configuration.

Node creation is the stage most likely to fail because it touches many host systems:

- file permissions and ACLs,
- base image formats,
- disk creation and resizing,
- cloud-init seed generation,
- libvirt domain XML,
- firmware selection,
- network attachment,
- SSH readiness.

Debug one node at a time by inspecting its rendered directory and console log.

## Provider inventory

`ard_provider_inventory` dispatches to provider-specific inventory generation. The libvirt implementation writes both persistent inventory and active in-memory Ansible hosts for the second apply play.

If `apply` creates VMs but the wait play cannot find hosts, inspect this role and the generated `inventory.yaml`.

## Provider destroy and cleanup

Destroy removes provider resources. Cleanup removes the local deployment workspace. Generated provider state exists to make destroy/debug flows more transparent.

The libvirt destroy path is state-first. When `provider-state.yaml` exists, destroy uses the recorded domain and network list rather than guessing from current presets. If state is missing, it falls back to finding domains with the deployment resource-name prefix and to the default management network name. This makes ordinary cleanup robust while still allowing manual recovery from partial or old workspaces.

Preserve generated artifacts by default after failures. They often contain exactly what you need: rendered XML, cloud-init data, inventory, state files, and log paths. Use `destroy-clean-generated` only when you no longer need those artifacts, or when you want a fresh generated workspace after resources are gone.

# Part VII - DevStack deployment layer reference

## DevStack configuration loading

Before running DevStack, `ard_devstack_config` loads deployment-specific variable files:

```text
devstack/common.yaml
devstack/group_vars/<group>.yaml
devstack/host_vars/<host>.yaml
```

This is the bridge between rendered ARD intent and ordinary Ansible variables used by DevStack roles.

## Common host preparation

`ansible/devstack_common.yaml` runs on all hosts and applies local roles plus upstream roles. It prepares stack user access, development tools, common DevStack settings, multinode SSH/bridge configuration, pip, and swap.

When a failure happens before DevStack itself runs, check this layer for missing OS packages, user setup problems, SSH peer issues, bridge setup, or role path/submodule problems.

## Controller deployment

`ansible/devstack_controller.yaml` runs the `devstack_controller` role on the `controller` group. This is where controller-side localrc/local.conf behavior and DevStack execution are managed.

Controller failures are usually visible in DevStack logs on the controller VM. SSH to the controller and inspect `/opt/stack`, `/opt/repos/devstack`, and DevStack log output.

## Compute deployment

`ansible/devstack_compute.yaml` runs the `devstack_compute` role on the `compute` group. Compute failures usually involve service enablement, controller connectivity, virtualization support, networking, or branch-specific DevStack behavior.

## Cache push and pull

`deploy_multinode_devstack.yaml` has local cache handling for apt/dnf, pip, and git repositories. The goal is to speed repeat deployments by pushing known caches to nodes and pulling caches back after a successful run.

Cache behavior can hide or reveal network issues. When debugging reproducibility, know whether a run used local cache data.

## vDPA and optional services

`vdpa.yaml` and the `configure_vdpa` role exist for vDPA-specific configuration. Service profiles and render overrides can enable related behavior. Treat specialized features as layers on top of the core render/apply/deploy flow.

# Part VIII - Molecule, validation, and test strategy

## Top-level Molecule scenarios

Top-level Molecule scenarios are full ARD/libvirt-backed DevStack validation flows. They use the same provider playbooks as Make and define ARD scenario intent under `provisioner.ard`.

Current top-level scenarios include:

```text
default
one-controller-two-compute
stable-2026.1
```

The create step is intentionally thin in each scenario: `molecule/<scenario>/create.yml` imports the shared `ansible/playbooks/ard-molecule-create.yaml` playbook. That shared playbook reads `molecule.yml`, validates the required `provisioner.ard` keys, writes generated render variables to `deployment/.molecule-render-vars.yaml`, runs `ard-render.yaml`, and then runs `ard-apply.yaml`. This keeps Molecule scenarios declarative and avoids duplicating render/apply command construction across scenarios.

The supported `provisioner.ard` fields include the provider, provider profile, deployment name, resource-name prefix, target branch, topology, service profiles, libvirt network name/CIDR, optional management network, optional render image, render overrides, and node overrides. Prefer adding scenario intent to `molecule.yml` instead of editing generated files under `molecule/<scenario>/deployment/`.

Run a full scenario with:

```bash
uv run molecule test -s default
```

For a cheaper loop:

```bash
uv run molecule create -s default
uv run ansible -i molecule/default/deployment/inventory.yaml all -m ping
uv run molecule converge -s default
uv run molecule verify -s default
uv run molecule destroy -s default
```

These scenarios require a host capable of running the local libvirt provider.

## Role-level Molecule scenarios

Some roles have their own Molecule scenarios under `ansible/roles/*/molecule`. These are intended for role-level validation where containers are sufficient.

Run all role scenarios discovered by the Makefile:

```bash
make molecule-test
```

Run one role scenario:

```bash
make molecule-role-ensure_kustomize
```

Role-level Molecule tests may require Podman.

## Cheap checks before expensive tests

Before running full libvirt/DevStack validation, use cheaper checks:

```bash
uv run ansible-playbook --syntax-check -i localhost, ansible/playbooks/ard-render.yaml
uv run ansible-playbook --syntax-check -i localhost, ansible/playbooks/ard-apply.yaml
uv run ansible-playbook --syntax-check -i localhost, ansible/playbooks/ard-destroy.yaml
make render ARD_DEPLOYMENT=syntax-devstack
```

A render-only test catches many data-model mistakes without starting VMs.

## Manual validation matrix

For provider/render changes, consider at least:

```text
make render ARD_TOPOLOGY=all-in-one
make render ARD_TOPOLOGY=one-controller-one-compute
make render ARD_TOPOLOGY=one-controller-two-compute
make render ARD_TARGET_BRANCH=stable/2026.1
make render ARD_SERVICES=devstack,ovn,tempest
make render ARD_SERVICES=devstack,ovn,tempest,ceph
make render with a custom ARD_RENDER_FILE
make render with ard_render_overrides
make apply + ping for the default topology
make deploy + verify for one representative full deployment
```

For DevStack role changes, a full deploy is more valuable than render-only checks.

# Part IX - Maintenance workflows

## Adding a topology preset

1. Add the topology to `ansible/roles/ard_provider_common/files/presets/topologies.yaml`.
2. Use existing node types where possible.
3. Ensure node names and IP/MAC generation are deterministic.
4. Decide whether the controller runs compute services.
5. Run render-only tests for the new topology.
6. Inspect `nodes.yaml`, controller group vars, and generated inventory.
7. Run at least `apply` and `ping` before declaring the topology usable.

Avoid inventing new group names unless necessary. Existing DevStack roles depend on current groups.

## Adding a service profile

1. Add the profile to `services.yaml`.
2. Decide whether it contributes node profiles, DevStack common vars, controller vars, compute vars, or a combination.
3. Keep profile behavior reusable and small.
4. Add README/developer-guide notes if the profile is user-facing.
5. Render with the new service in combination with default services.
6. Run a full deployment if the profile changes DevStack behavior.

## Adding an image or flavor

Images and flavors live in provider common defaults today.

When adding an image:

- include a stable key,
- specify OS family/version metadata,
- define provider-specific URL/name/cache filename/format,
- consider whether checksums should be required,
- test image download and cloud-init behavior.

When adding a flavor:

- document CPU, memory, and disk expectations,
- include provider-specific libvirt values,
- verify the size is realistic for DevStack,
- avoid making defaults too small for successful deployments.

## Adding a provider

The design supports provider isolation, but the current implementation is libvirt-oriented. A new provider likely needs:

```text
ard_<provider>_preflight
ard_<provider>_image
ard_<provider>_network
ard_<provider>_node
ard_<provider>_inventory
ard_<provider>_destroy
```

You may also need provider-specific render output and validation changes. The provider must eventually produce the same logical inventory contract used by the DevStack layer.

Keep the DevStack roles provider-agnostic. Do not make `devstack_common`, `devstack_controller`, or `devstack_compute` know about libvirt/KubeVirt unless there is no other option.

## Updating submodules

Submodules provide DevStack and Zuul roles. When updating them:

1. update the submodule pointer,
2. run syntax checks,
3. run render-only checks,
4. run at least one full deployment scenario,
5. inspect role-name conflicts or behavior changes,
6. document any required variable changes.

Submodule updates can change role behavior even if ARD code did not change.

## Editing generated examples

Do not manually edit generated files under `deployments/<name>/` and commit them as source unless the repository intentionally starts tracking a fixture. Most deployment workspaces are local scratch state.

Prefer examples under `examples/` or Molecule scenario definitions when you need checked-in user-facing intent.

# Part X - Troubleshooting

## Decide which layer failed

First classify the failure:

```text
bootstrap failure       host packages, uv, bindep, submodules, libvirt commands
render failure          bad variables, missing presets, invalid topology/network/service input
image failure           image URL/cache/checksum/download/path/ACL issue
network failure         libvirt network XML, net-define, net-start, CIDR conflict
node failure            cloud-init seed, qcow2, ACLs, firmware, domain XML, virsh start
inventory failure       wrong management IP, missing groups, generated inventory syntax
readiness failure       SSH, cloud-init, guest networking, stack user/key setup
DevStack common failure OS packages, users, bridges, role path, upstream roles
controller failure      local.conf/localrc, run-devstack, OpenStack services
compute failure         subnode sync, nova-compute, networking, controller reachability
verify failure          inventory, DevStack checkout, Tempest smoke
```

Do not debug DevStack logs before confirming that provider nodes are reachable and cloud-init completed.

## Libvirt access

Symptoms:

```text
virsh cannot connect to qemu:///system
permission denied on libvirt socket
network/domain define fails unexpectedly
```

Checks:

```bash
virsh --connect qemu:///system uri
groups
systemctl status libvirtd || systemctl status virtqemud
```

Your user may need membership in a libvirt or qemu group. After changing group membership, log out and back in or use `newgrp`.

## CIDR conflicts

If a libvirt network fails to start or nodes cannot route, check whether the selected `ARD_NETWORK_CIDR` conflicts with existing host networks or another ARD deployment.

Use unique deployment names and CIDRs for parallel deployments:

```bash
make render ARD_DEPLOYMENT=devstack-a ARD_NETWORK_CIDR=192.168.99.0/24
make render ARD_DEPLOYMENT=devstack-b ARD_NETWORK_CIDR=192.168.100.0/24
```

## UEFI firmware problems

Libvirt firmware auto-selection is used for UEFI boot with secure boot disabled. If domain definition or boot fails because firmware cannot be found, install the OVMF/edk2 firmware package for your distribution.

## SSH not ready

`apply` waits for SSH and cloud-init. If it times out:

1. inspect the generated inventory IP,
2. inspect `provider-state.yaml`,
3. inspect the node's rendered cloud-init files,
4. inspect the serial console log path recorded in provider state,
5. verify the libvirt domain is running,
6. verify the libvirt network is active,
7. retry `make apply` after fixing the underlying issue.

## Cloud-init problems

Inspect per-node rendered files:

```text
deployments/<name>/rendered/libvirt/<node>/user-data
deployments/<name>/rendered/libvirt/<node>/meta-data
deployments/<name>/rendered/libvirt/<node>/network-config
```

Inside the guest, inspect:

```bash
sudo cloud-init status --long
sudo journalctl -u cloud-init --no-pager
sudo journalctl -u ssh --no-pager
ip addr
ip route
```

## DevStack failures

Once SSH works and cloud-init is complete, switch your attention to DevStack logs and role output.

Useful locations on the controller commonly include:

```text
/opt/repos/devstack
/opt/stack
/tmp/zuul_logs
```

Use `make ssh` to enter the controller, then inspect service logs and DevStack output according to the failing role/task.

## Cleaning up stuck resources

Prefer ARD cleanup first:

```bash
make destroy ARD_DEPLOYMENT=<name>
make destroy-clean-generated ARD_DEPLOYMENT=<name>
```

If manual cleanup is required, inspect `provider-state.yaml` before deleting resources. It records the libvirt resource names and local disk/seed/log paths.

Manual libvirt commands can be destructive. Verify names before running commands such as `virsh destroy`, `virsh undefine`, `virsh net-destroy`, or `virsh net-undefine`.

# Part XI - Quick reference

## Core commands

```bash
./bootstrap-repo.sh
make render ARD_DEPLOYMENT=devstack-a
make apply ARD_DEPLOYMENT=devstack-a
make ping ARD_DEPLOYMENT=devstack-a
make ssh ARD_DEPLOYMENT=devstack-a ARD_NODE=controller
make ssh-print ARD_DEPLOYMENT=devstack-a ARD_NODE=compute-1
make deploy ARD_DEPLOYMENT=devstack-a
make verify ARD_DEPLOYMENT=devstack-a
make destroy ARD_DEPLOYMENT=devstack-a
make destroy-clean-generated ARD_DEPLOYMENT=devstack-a
make cleanup ARD_DEPLOYMENT=devstack-a
```

## Render examples

```bash
make render \
  ARD_DEPLOYMENT=devstack-a \
  ARD_TARGET_BRANCH=master \
  ARD_TOPOLOGY=one-controller-two-compute \
  ARD_SERVICES=devstack,ovn,tempest \
  ARD_NETWORK_CIDR=192.168.99.0/24
```

```bash
make render \
  ARD_DEPLOYMENT=stable-test \
  ARD_RENDER_FILE=path/to/render.yaml
```

## Topology names

```text
all-in-one
one-controller-one-compute
one-controller-two-compute
```

## Service profile names

```text
devstack
ovn
tempest
ceph
```

## Image keys

```text
debian-13
ubuntu-24.04
```

## Flavor keys

```text
devstack-control
devstack-compute
```

## Important generated files

```text
deployments/<name>/deployment.yaml
deployments/<name>/nodes.yaml
deployments/<name>/devstack/common.yaml
deployments/<name>/devstack/group_vars/controller.yaml
deployments/<name>/devstack/group_vars/compute.yaml
deployments/<name>/inventory.yaml
deployments/<name>/provider-state.yaml
deployments/<name>/rendered/libvirt/<node>/user-data
deployments/<name>/rendered/libvirt/<node>/meta-data
deployments/<name>/rendered/libvirt/<node>/network-config
deployments/<name>/rendered/libvirt/<node>/domain.xml
molecule/<scenario>/deployment/.molecule-render-vars.yaml
```

## Important source files

```text
Makefile
bootstrap-repo.sh
bindep.txt
pyproject.toml
ansible.cfg
ansible/playbooks/ard-render.yaml
ansible/playbooks/ard-apply.yaml
ansible/playbooks/ard-molecule-create.yaml
ansible/playbooks/ard-deploy-devstack.yaml
ansible/playbooks/ard-verify.yaml
ansible/playbooks/ard-destroy.yaml
ansible/playbooks/ard-cleanup.yaml
ansible/roles/ard_provider_common/defaults/main.yml
ansible/roles/ard_provider_common/files/presets/*.yaml
ansible/roles/ard_provider_render/tasks/main.yml
ansible/roles/ard_provider_render/templates/nodes.yaml.j2
ansible/roles/ard_libvirt_image/tasks/main.yml
ansible/roles/ard_libvirt_network/tasks/main.yml
ansible/roles/ard_libvirt_node/tasks/main.yml
ansible/roles/ard_libvirt_node/tasks/node.yml
ansible/roles/ard_libvirt_inventory/tasks/main.yml
ansible/deploy_multinode_devstack.yaml
ansible/devstack_common.yaml
ansible/devstack_controller.yaml
ansible/devstack_compute.yaml
ansible/roles/ard_devstack_config/tasks/main.yml
scripts/ard-ssh
molecule/*/molecule.yml
```

## Contributor rule of thumb

When changing ARD, identify the layer first:

```text
render data model       presets, render tasks, nodes template, generated workspace files
provider behavior       ard_provider_* dispatchers and ard_libvirt_* roles
inventory contract      ard_libvirt_inventory and DevStack group expectations
DevStack behavior       ard_devstack_config, deploy_multinode_devstack, devstack_* roles
local UX                Makefile, bootstrap-repo.sh, scripts/ard-ssh, README.md
validation              Molecule scenarios and role-level Molecule tests
```

Then choose the cheapest validation that exercises that layer. Render changes usually deserve render-only checks across topologies. Provider changes deserve `apply` and `ping`. DevStack changes deserve a full `deploy` and `verify` on at least one representative topology.
