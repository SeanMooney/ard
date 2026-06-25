# ARD render model

This document is the user-facing map for ARD render files and examples. Use it
when choosing or adapting an example from `examples/` for Make, Molecule, or a
direct Ansible run. Contributor-level invariants are documented in
[`../architecture/render-contracts.md`](../architecture/render-contracts.md).

## Examples are the primary interface

The `examples/` tree is the public catalog of reusable deployment intent. An
example says what kind of environment to build: workload family, topology,
service profiles, branch/image choices, and small provider defaults. The same
example can be consumed three ways:

```bash
# Make
make render ARD_DEPLOYMENT=devstack-a \
  ARD_RENDER_FILE=examples/devstack/aio-plus-compute/render.yaml

# Direct Ansible
uv run ansible-playbook -i localhost, ansible/playbooks/provider/render.yaml \
  -e ard_deployment_name=devstack-a \
  -e @examples/devstack/aio-plus-compute/render.yaml

# Molecule
# molecule/<scenario>/molecule.yml sets provisioner.ard_render_file and keeps
# scenario-only values, such as deployment name and CIDR, under provisioner.ard.
uv run molecule create -s default
```

Make variables and Molecule `provisioner.ard` values are overrides. They should
select provider execution details or scenario-local identity, not duplicate the
whole example. Public examples include `ard_render_schema_version: 1` so the
renderer can distinguish the current contract from older unversioned inputs.

Current example families include:

- `examples/devstack/` — upstream OpenStack development with DevStack.
- `examples/microshift/` — local MicroShift substrate environments.
- `examples/oko/` — OpenStack-on-OpenShift/operator installer environments with
  MicroShift and EDPM-style compute nodes.
- `examples/provider-test/` — small provider smoke-test shapes.

## Providers and provider profiles

A provider creates resources. Current providers include `libvirt`, `kubevirt`,
and `static` for pre-provisioned SSH hosts. A provider profile selects provider
implementation defaults and maps abstract node classes to concrete shapes:

```yaml
ard_provider: libvirt
ard_provider_profile: local-libvirt
```

or:

```yaml
ard_provider: kubevirt
ard_provider_profile: kubevirt
ard_kubevirt_namespace: my-namespace
```

Providers do not define workload vocabulary such as "DevStack controller" or
"EDPM compute". Those are workload concepts. Provider profiles answer questions
such as "what libvirt flavor should a `large` node use?" or "what KubeVirt VM
preference should a `default` node use?".

## Deployment identity and provider resource names

ARD separates three identities:

```yaml
ard_deployment_name: devstack-a
ard_provider_resource_prefix: ard-devstack-a
ard_deployment_dir: deployments/devstack-a
```

- `ard_deployment_name` is the logical deployment name used in examples,
  inventories, and user-facing commands.
- `ard_provider_resource_prefix` is the prefix for real provider resources.
  Libvirt commonly derives it from the deployment name. KubeVirt should include
  `ard_user` by default so users sharing a namespace do not collide.
- `ard_deployment_dir` is the durable workspace containing rendered inputs,
  generated inventory, and provider state.

Inventory hostnames stay logical (`controller`, `compute-1`,
`edpm-compute-1`). Provider resources are collision-safe names such as
`ard-devstack-a-controller` or `<user>-devstack-a-controller`.

Compatibility aliases such as `ARD_DEPLOYMENT`, `ard_resource_name_prefix`, and
provider-specific network-name variables are still accepted, but new render
files should use the canonical names above.

## Deployment-local intent and local vars

A deployment workspace can carry both persistent render intent and local
lifecycle variables:

```text
deployments/<deployment>/render.yaml      # provider, topology, image, naming intent
deployments/<deployment>/local-vars.yaml  # site-local and workload deploy inputs
```

Use `render.yaml` for values that affect rendered provider/topology state, such
as `ard_provider`, `ard_provider_profile`, `ard_topology`, image choices,
namespace, and KubeVirt access mode. Use `local-vars.yaml` for variables consumed
by apply/deploy lifecycle playbooks, such as local proxy configuration or
workload-specific development inputs. Make automatically loads
`local-vars.yaml` for lifecycle targets when it exists.

For example, an OKO development deployment that tests pre-merge operator PRs can
keep provider intent in `render.yaml` and put the PR source overrides in
`local-vars.yaml`:

```yaml
# deployments/oko-cyborg/local-vars.yaml
---
oko_dev_tools_enabled: true
oko_dev_repos:
  - name: nova-operator
    repo: https://github.com/openstack-k8s-operators/nova-operator
    base_branch: main
    ref: pull/1102/head
    go_prep: true
    nfs_export: false

  - name: edpm-ansible
    repo: https://github.com/openstack-k8s-operators/edpm-ansible
    base_branch: main
    ref: pull/1180/head
    go_prep: false
    nfs_export: true
    nfs_mount_path: /usr/share/ansible/collections/ansible_collections/osp/edpm
```

`edpm-ansible` is exported so ansibleee runner pods can consume the development
collection content without rebuilding the runner image. Site-specific proxy or
DNS values can live in the same `local-vars.yaml`, but reusable examples should
avoid embedding site-only proxy configuration.

After render, subsequent Make commands can use just the logical deployment name.
The workspace remains the logical deployment directory; provider resources may
still be user-prefixed for shared-tenancy safety:

```bash
make render ARD_DEPLOYMENT=oko-cyborg
make apply ARD_DEPLOYMENT=oko-cyborg
make deploy ARD_DEPLOYMENT=oko-cyborg
```

For KubeVirt OKO, `make apply` creates the provider resources and generated
inventory, matching Molecule create behavior. `make deploy` runs the KubeVirt OKO
converge flow: MicroShift setup, ARD multinode bridge overlay setup, and full
OKO network/control-plane/dataplane application.

## Workload families, workloads, and topologies

A workload family owns defaults and vocabulary for one kind of environment:

- `devstack`: DevStack branch, service profile, and controller/compute behavior.
- `microshift`: MicroShift node defaults and image selection.
- `oko`: MicroShift control-plane substrate plus EDPM compute behavior.

A workload topology composes node pools for that family. For example:

```yaml
ard_workload: devstack
ard_workload_topology: aio-plus-compute
```

means one large AIO/controller node plus one default compute node. Older global
`ard_topology` names such as `one-controller-one-compute` remain aliases for
compatibility, but new examples should prefer family-aware workload/topology
names when available.

## Node pools, node classes, and workload roles

A node pool describes one or more similar logical nodes. A pool requests an
abstract class such as `large`, `medium`, `default`, `small`, or `extra-small`.
The selected provider profile maps that class to a real provider flavor or VM
preference.

Workload roles describe what a node does and which Ansible inventory groups it
joins. Examples:

- `devstack_controller` -> `controller`, `switch`
- `devstack_compute` -> `compute`, `peers`, `subnode`
- `microshift_node` -> `microshift`
- `edpm_compute` -> `compute`, `peers`, `subnode`

A DevStack all-in-one node is modeled by assigning both `devstack_controller`
and `devstack_compute` to the same node pool. OKO EDPM nodes use
`edpm_compute`, not generic DevStack controller semantics.

## Networks and provider capability validation

Examples use provider-neutral network names such as `ard-mgmt` and
`datacenter`. The renderer resolves those names through network presets and the
selected provider profile. The profile advertises supported network names and
modes, for example NAT and isolated networks.

If an example requests a network or mode that the provider profile cannot
support, render fails before provider resources are created. For libvirt,
`ard_libvirt_network_cidr` can override the management CIDR. For KubeVirt, the
same logical network names are mapped to provider resources in the selected
namespace.

## Branches, images, services, and role-specific targeting

Workload families own workload compatibility defaults. For example, a DevStack
stable branch can imply an Ubuntu image because that is a DevStack compatibility
choice, not a generic provider default. MicroShift and OKO own their control
plane and EDPM image defaults.

Image and service choices can be applied globally, by workload, by role, by
pool, or by node override. Role-specific image variables let OKO render a
MicroShift node and EDPM compute nodes from different images in one topology.

## Molecule merge behavior

Molecule scenarios normally point to an external example with
`provisioner.ard_render_file`. Inline `provisioner.ard` is an override map. In
schema version 1:

- scalar values replace earlier values;
- dictionaries deep-merge by key;
- lists replace earlier lists wholesale;
- scenario-forced values such as the deployment directory win last.

This means a Molecule scenario can override deployment identity, provider,
namespace, or network CIDR without copying the example.

## Persisted state and destroy

Render/apply writes durable artifacts under `ard_deployment_dir`, including
`deployment.yaml`, `nodes.yaml`, generated inventory, rendered provider files,
and `provider-state.yaml`. Destroy uses persisted state where possible instead
of recomputing resource names from current defaults. This protects cleanup when
provider naming rules, usernames, profiles, or default CIDRs change after a
deployment was created.
