# Render contracts

This document records the contributor-facing contracts for the completed ARD
render model. User concepts are introduced in
[`../concepts/ard-render-model.md`](../concepts/ard-render-model.md). Keep code,
presets, examples, and Molecule integration aligned with these contracts.

## Render input schema

Public render examples use schema version 1:

```yaml
ard_render_schema_version: 1
```

Contract:

- The Molecule render-file loader supports a declared maximum schema version,
  currently `1`.
- In Molecule, a render file with a version greater than the loader supports is
  a hard error.
- Missing `ard_render_schema_version` means legacy/unversioned input. It may be
  accepted only through compatibility normalization.
- Molecule inline `provisioner.ard` inherits the version from
  `provisioner.ard_render_file`.
- If inline Molecule data supplies `ard_render_schema_version`, it must match the
  external render file and the supported loader version.
- Molecule version checks happen before semantic normalization. The merged
  normalized configuration is validated again after aliases and overrides are
  applied.
- Direct `ansible-playbook ... render.yaml -e @example/render.yaml` and Make
  render paths currently treat `ard_render_schema_version` as example metadata;
  schema-version enforcement for those direct paths is a future compatibility
  hardening item.

Schema v1 does not define implicit environment-variable or Jinja expansion for
`ard_render_file`; relative Molecule render-file paths are resolved relative to
the scenario directory.

## Input sources, preset load order, and merge semantics

The renderer builds a deployment from presets plus user intent. Conceptually:

1. Provider-common preset files under
   `ansible/roles/ard_provider_common/files/presets/` are loaded.
2. External render intent is loaded, usually from `examples/*/*/render.yaml`.
3. Compatibility aliases are normalized to canonical variables.
4. CLI, Make, direct Ansible `-e`, or Molecule inline overrides are merged.
5. Scenario-forced values such as Molecule deployment directories are applied.
6. The normalized merged configuration is validated and rendered.

Schema v1 merge semantics are deliberately simple:

- Scalars replace earlier values.
- Dictionaries deep-merge by key unless a specific contract says otherwise.
- Lists replace earlier lists wholesale, including workload profile, node-pool,
  and network lists.
- There is no hidden merge-by-name for structured lists.
- Partial updates to lists require either a future explicit patch syntax or a
  future schema version.

`ard_render_overrides` uses recursive dictionary merge semantics for its named
sections. Pool override maps are keyed by pool name. Node overrides are keyed by
final logical node name.

## Compatibility aliases and conflicts

Canonical variables should be used in new examples and migrated Molecule
scenarios. Compatibility aliases remain accepted to avoid breaking existing
callers.

Important aliases include:

```text
ARD_DEPLOYMENT               -> ard_deployment_name
ard_resource_name_prefix     -> ard_provider_resource_prefix
resource_name_prefix         -> ard_provider_resource_prefix (Molecule legacy)
ard_target_branch            -> ard_devstack_branch
ard_render_image / ARD_IMAGE -> workload image variable where applicable
ard_topology                 -> ard_workload + ard_workload_topology alias
```

Global topology aliases are:

```text
all-in-one                  -> devstack/all-in-one
one-controller-one-compute  -> devstack/aio-plus-compute
one-controller-two-compute  -> devstack/one-controller-two-compute
microshift-single-node      -> microshift/single-node
oko-microshift-two-compute  -> oko/microshift-two-edpm-compute
```

If `ard_workload` is missing and a topology alias or namespaced topology implies
a workload, normalization infers it. If canonical and compatibility values both
exist:

- matching values are accepted;
- conflicting values select the canonical variable;
- Molecule render-file loading warns with both variable names and the ignored
  value when it can detect the conflict;
- direct render paths may resolve the effective canonical value without a warning
  until equivalent conflict diagnostics are added there;
- future strict-validation mode may turn conflicts into errors.

## Provider identity contract

Logical deployment identity, provider resource identity, and persisted artifact
location are separate:

```yaml
ard_deployment_name: devstack-a
ard_provider_resource_prefix: ard-devstack-a
ard_deployment_dir: deployments/devstack-a
```

- `ard_deployment_name` is user-facing and logical.
- `ard_provider_resource_prefix` is provider-specific and is used when building
  real resource names.
- `ard_deployment_dir` stores generated and persisted deployment artifacts.

Providers must use `ard_provider_resource_prefix` when creating, finding, and
destroying concrete resources. Inventory hostnames are workload/logical names
and must not be prefixed for collision avoidance.

For libvirt, the default provider prefix may be derived from the deployment name
and project convention, for example `ard-<deployment>`. For KubeVirt, the
default prefix should include `ard_user` to avoid collisions in a shared
namespace. KubeVirt resource names must be validated after prefix and node suffix
expansion against Kubernetes/RFC1123 DNS-label requirements and the 63-character
limit where that limit applies.

KubeVirt legacy identity migration:

- Existing inputs may have `ard_deployment_name` already user-prefixed.
- Normalized state records both the logical deployment name and concrete
  provider prefix when possible.
- `ard_resource_name_prefix` remains an alias for
  `ard_provider_resource_prefix`.
- Destroy must read old persisted state where only `ard_deployment_name` exists
  and treat that value as the provider resource prefix.

## Provider profile and node-class contract

A provider profile selects one provider implementation and maps abstract intent
to concrete provider parameters. Profiles live in provider presets and include:

- `provider`: implementation name, such as `libvirt`, `kubevirt`, or `static`;
- `provider_defaults`: generic defaults such as image, flavor, or VM preference;
- `provider_node_class_defaults`: mapping from node class to concrete flavor or
  preference;
- `capabilities`: supported provider features, network names, and modes.

Node classes are provider-neutral capacity requests. Current classes are
`large`, `medium`, `default`, `small`, and `extra-small`. Topologies and node
pools request classes; provider profiles resolve them to provider-specific
flavors. New workload presets must not introduce provider-owned vocabulary such
as `controller_flavor` as the primary model, although compatibility fields can
remain until all callers migrate.

## Workload family, topology, pool, and role contracts

A workload family owns vocabulary, defaults, and compatibility rules for a class
of environment. Current families are `devstack`, `microshift`, and `oko`.

A workload topology is scoped to a workload family and defines node pools. A
pool may define:

- `name` or `name_format` for logical node names;
- `hostname` or `hostname_format`;
- `count`;
- `class`;
- `workload_roles`;
- `networks`;
- pool-specific image/profile/network details;
- compatibility `type` while older node-type mappings remain supported.

Workload roles map nodes to Ansible groups and behavior. The current role map is
maintained in `node-types.yaml`:

- DevStack `devstack_controller`: `controller`, `switch`.
- DevStack `devstack_compute`: `compute`, `peers`, `subnode`.
- MicroShift/OKO `microshift_node`: `microshift`.
- OKO `edpm_compute`: `compute`, `peers`, `subnode`.

A DevStack all-in-one node is represented by both controller and compute roles
on one pool. OKO EDPM nodes must use the EDPM role so image and inventory
semantics can differ from generic DevStack compute nodes.

## Networks and capability validation

Network capability validation is part of the render contract. Render examples express provider-neutral network intent. Network presets define
logical networks such as `ard-mgmt` and `datacenter`, including mode,
provider-network name, and MAC defaults. Provider profiles advertise supported
network names and modes.

Validation requirements:

- Every requested logical network must exist in the network preset map or in
  explicit overrides.
- Every requested network mode must be supported by the selected provider
  profile.
- If a provider profile restricts network names, every requested network must be
  allowed by that profile.
- Provider-specific aliases such as libvirt network names are normalized before
  rendering provider artifacts.

Validation must fail before any provider resources are created.

## Image, flavor, profile, and role/pool targeting

Resolution order should keep workload compatibility choices out of provider
profiles. The general precedence is:

1. explicit node override;
2. pool-specific values;
3. workload-role defaults, including role-specific `image_var` entries;
4. workload family/profile/branch defaults;
5. provider node-class defaults;
6. provider defaults.

DevStack branch presets may set DevStack-specific image defaults, such as using
`ubuntu-24.04` for `stable/2026.1`. MicroShift and OKO presets own MicroShift
and EDPM image defaults. Role-specific image variables allow mixed topologies,
such as OKO's MicroShift control-plane node plus EDPM compute nodes, to render
correctly without provider-specific example duplication.

Node profiles from pools, workload roles, service profiles, and provider/profile
defaults are combined without dropping existing behavior such as `ssh` and
`nested_virt`.

## Generated files and persisted destroy state

The deployment directory is the durable contract between render, apply, verify,
destroy, and cleanup. It may contain:

```text
deployment.yaml          # normalized provider/deployment data
nodes.yaml               # normalized logical nodes and provider names
devstack/*.yaml          # workload-specific rendered vars when applicable
inventory.yaml           # generated by apply/inventory roles
provider-state.yaml      # persisted provider resource identity/state
rendered/                # provider artifacts
logs/                    # runtime logs
```

Destroy roles must prefer persisted `provider-state.yaml`, `nodes.yaml`, and
rendered provider names instead of recomputing names from current defaults.
This is required for safe cleanup after changes to users, namespaces, provider
profiles, resource-prefix defaults, or network defaults. If state is missing,
roles may fall back to compatibility behavior, but that path should be explicit
and conservative.

`make destroy` removes provider resources and keeps the workspace for
inspection. `make destroy-clean-generated` additionally removes generated
inventory/state/rendered artifacts. `make cleanup` removes the local deployment
workspace only after resources are no longer needed.

## Molecule render-file contract

Migrated Molecule scenarios use:

```yaml
provisioner:
  ard_render_file: ../../examples/devstack/aio-plus-compute/render.yaml
  ard:
    ard_deployment_name: molecule-example
    ard_provider_resource_prefix: ard-molecule-example
```

Contract:

- `provisioner.ard_render_file` is the base render intent.
- Inline `provisioner.ard` is an override map using canonical `ard_*` names.
- The merge order is external example, inline overrides, then forced
  scenario-local deployment directory/state paths.
- The merged canonical variables are written to the scenario deployment
  workspace for the normal render/apply path.
- KubeVirt scenarios may override provider, profile, namespace, and identity but
  should still consume the same example catalog when possible.

## Validation expectations

Representative low-cost validation for documentation or render-model changes is
limited to static checks and render-only commands. Do not run long deploy tests
for documentation-only changes. Useful checks include:

```bash
make render ARD_DEPLOYMENT=doc-check \
  ARD_RENDER_FILE=examples/devstack/aio-plus-compute/render.yaml \
  ARD_PROVIDER=libvirt ARD_PROVIDER_PROFILE=local-libvirt

make render ARD_DEPLOYMENT=doc-check-kv \
  ARD_RENDER_FILE=examples/devstack/aio-plus-compute/render.yaml \
  ARD_PROVIDER=kubevirt ARD_PROVIDER_PROFILE=kubevirt \
  ARD_USER=<user> ARD_KUBEVIRT_NAMESPACE=<namespace>
```

For this contract, a valid representative render should show that examples carry
`ard_render_schema_version: 1`, provider prefixes are persisted, node classes map
to provider shapes, provider networks validate, role-specific image targeting is
preserved, and destroy-state artifacts contain enough resolved state for cleanup.
