# MicroShift Deployment Plan

## Goals

- Add MicroShift as an ARD workload that can run on provider-managed VMs.
- Start with an RPM-based installation path.
- Add a bootc/image-mode path after the RPM path is working.
- Use upstream MicroShift packages; do not build MicroShift from source in ARD.
- Add EL-family cloud images to the standard ARD image set and default the MicroShift workload to CentOS Stream 10.

## Non-goals

- Do not preserve the old `ensure_microshift` implementation as the target design.
- Do not require local MicroShift source builds.
- Do not assume RHSM/subscription-manager for the default CentOS Stream 10 workflow.
- Do not make DevStack default to CentOS Stream 10 globally unless we intentionally change the provider defaults separately.

## Current references

- ARD image registry currently lives in `ansible/roles/ard_provider_common/defaults/main.yml` under `ard_images`.
- Current standard image keys are `debian-13` and `ubuntu-24.04`.
- Existing MicroShift workload entry point: `ansible/playbooks/workloads/microshift/deploy.yaml`.
- Existing role: `ansible/roles/ensure_microshift/`.
- Upstream docs reviewed from `~/repos/microshift/docs/run.md` and `~/repos/microshift/docs/run-bootc.md`.

## Standard image additions

Add these image keys to `ard_images`:

| Image key | Family | Purpose |
| --- | --- | --- |
| `centos-stream-10` | Red Hat-like | Default MicroShift RPM target |
| `fedora-eln` | Red Hat-like | Early validation against next-generation Fedora/RHEL content |
| `almalinux-10` | Red Hat-like | RHEL-compatible community target |
| `rocky-linux-10` | Red Hat-like | RHEL-compatible community target |

Each image definition should include the same provider metadata as existing images:

- `os_family`
- `version`
- `cloud_init: true`
- `provider.libvirt.url`
- `provider.libvirt.name`
- `provider.libvirt.cache_filename`
- `provider.libvirt.format: qcow2`
- `provider.libvirt.cloud_init_datasource: NoCloud`

Candidate cloud image URLs should be verified before implementation because CentOS Stream 10, AlmaLinux 10, Rocky Linux 10, and Fedora ELN naming may still change. Expected starting points:

- CentOS Stream: `https://cloud.centos.org/centos/10-stream/x86_64/images/`
- Fedora ELN: `https://download.fedoraproject.org/pub/fedora/linux/development/eln/Cloud/x86_64/images/`
- AlmaLinux: `https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/`
- Rocky Linux: `https://dl.rockylinux.org/pub/rocky/10/images/x86_64/`

## Deployment modes

### Phase 1: RPM install

Use upstream-available MicroShift RPM packages. The upstream host deployment flow is:

1. Enable the configured upstream MicroShift RPM package source. The source should be configurable through `microshift_rpm_channel`, similar to how DevStack branch selection is configurable through `ard_target_branch`. The default channel is `github-release`, using the MicroShift GitHub release RPM bundle for `4.20.0_g153ff0ca9_4.20.0_okd_scos.16`. COPR and custom repository URLs remain explicit override modes.
2. Install `microshift-io-dependencies` only when using a COPR path; the GitHub release path uses the release RPM bundle and the matching dependency repository helper.
3. Install `microshift` plus the default OVN-K networking package:
   - `microshift-networking` is the default and expected path.
   - `microshift-kindnet` may remain as an explicit override for simpler experiments, but is not the default plan.
4. Install default storage and operator packages:
   - `microshift-topolvm`
   - `microshift-olm`
5. Run upstream post-install host configuration when appropriate: `src/rpm/postinstall.sh` behavior should be translated into idempotent Ansible tasks or called from the installed package if packaged.
6. Start and enable `microshift.service`.
7. Copy `/var/lib/microshift/resources/kubeadmin/kubeconfig` to the workload user.
8. Validate with Kubernetes client commands.

### Phase 2: bootc/image-mode

After RPM mode works, add a separate bootc path rather than overloading RPM tasks.

The upstream bootc docs describe running MicroShift inside a bootc container with make targets from the source tree. ARD should instead model the deployable outcome:

- choose or build a bootc image outside the runtime deployment path;
- provision a VM from the selected bootc-capable image;
- apply host/runtime prep required for TopoLVM, networking, and kubeconfig extraction;
- validate service health the same way as RPM mode.

Keep bootc variables separate from RPM variables so the inventory can select:

```yaml
microshift_deployment_mode: rpm   # later: bootc
```

## Proposed Ansible structure

Replace the old all-in-one `ensure_microshift` behavior with small roles or task files:

```text
ansible/playbooks/workloads/microshift/deploy.yaml
ansible/roles/microshift_prereqs/
ansible/roles/microshift_repos/
ansible/roles/microshift_install_rpm/
ansible/roles/microshift_install_bootc/      # phase 2
ansible/roles/microshift_config/
ansible/roles/microshift_validate/
```

Suggested responsibilities:

- `microshift_prereqs`: OS detection, required base packages, firewall service availability, SELinux/firewalld checks, NetworkManager assumptions, client tools.
- `microshift_repos`: package source setup for upstream MicroShift packages.
- `microshift_install_rpm`: package selection and `microshift.service` enable/start for RPM hosts.
- `microshift_install_bootc`: bootc/image-mode host integration after phase 1.
- `microshift_config`: kubeconfig placement and optional MicroShift config files.
- `microshift_validate`: wait for API, node readiness, and pods.

## Storage defaults

MicroShift should install two storage providers by default:

1. TopoLVM via the MicroShift package support, using `microshift-topolvm`.
2. Rancher Labs Local Path Provisioner as a post-install Kubernetes deployment.

TopoLVM is the closer MicroShift-integrated storage path. Local Path Provisioner provides a simple host-path backed option for workloads and tests that do not need LVM-backed dynamic volumes. The implementation should keep these independently toggleable.

The default value of the configurable `microshift_default_storage_class` variable should be `local-path`, making the Rancher Labs Local Path Provisioner / host-path storage class the default `StorageClass`. TopoLVM is available as an opt-in storage provider, but is disabled by default for the current CentOS Stream 10/GitHub release path. Scenarios can enable it and select it as the default by setting `microshift_install_topolvm: true` and `microshift_default_storage_class: topolvm`.

## Post-install operators and add-ons

OLM should be installed by default with `microshift-olm` so ARD can install operators after the base cluster is healthy.

Initial planned post-install add-ons:

- MetalLB
- Rancher Labs Local Path Provisioner
- future user-selected operators

MetalLB and future operators should be treated as post-install workload add-ons, not part of the base MicroShift RPM install itself.

## Workload defaults

The MicroShift workload should override the rendered provider image to CentOS Stream 10 without changing DevStack defaults:

```yaml
ard_render_image: centos-stream-10
microshift_deployment_mode: rpm
microshift_rpm_channel: github-release
microshift_release_tag: 4.20.0_g153ff0ca9_4.20.0_okd_scos.16
microshift_networking: ovnk
microshift_install_topolvm: false
microshift_install_local_path_provisioner: true
microshift_default_storage_class: local-path
microshift_install_olm: true
microshift_postinstall_operators:
  - metallb
```

The provider-level default can remain `debian-13` until ARD intentionally changes the global default.

## Configurable defaults

These defaults should be configurable per deployment/render file:

```yaml
microshift_rpm_channel: github-release
microshift_release_tag: 4.20.0_g153ff0ca9_4.20.0_okd_scos.16
microshift_release_rpm_url: "https://github.com/microshift-io/microshift/releases/download/{{ microshift_release_tag }}/microshift-rpms-{{ ansible_architecture }}.tgz"
microshift_rpm_copr: '@microshift-io/microshift'
microshift_rpm_repo_url: null
microshift_default_storage_class: local-path
```

`microshift_rpm_channel` selects the package source mode. The default is `github-release`, using the configured MicroShift GitHub release RPM bundle; supported override modes include `copr-stable`, `copr-nightly`, and custom repo URLs. COPR was de-prioritized for now because both nightly and stable COPR paths had dependency/repository issues on CentOS Stream 10 during validation.

`microshift_default_storage_class` selects which installed storage provider is marked as the cluster default. Initial valid values should be `local-path` and `topolvm`.



For now, ARD should select the workload through a variable instead of adding a dedicated MicroShift make target. The default workload can remain DevStack, while MicroShift is selected explicitly:

```bash
make deploy ARD_WORKLOAD=microshift
```

## Inventory and group model

Use a dedicated MicroShift workload group instead of reusing `openshift` naming from the old playbook:

```yaml
microshift:
  hosts:
    controller:
```

For single-node default topology, `controller` is sufficient. Future multi-node MicroShift or bootc testing can add additional node pools after the first workflow is stable.

## Validation plan

Minimum validation tasks:

```bash
systemctl is-active microshift.service
kubectl --kubeconfig /var/lib/microshift/resources/kubeadmin/kubeconfig get nodes
kubectl --kubeconfig /var/lib/microshift/resources/kubeadmin/kubeconfig get pods -A
```

Ansible validation should:

- wait for kubeconfig to exist;
- install or provide `kubectl`/`oc` only when missing;
- retry node/pod readiness for a bounded time;
- collect `journalctl -u microshift.service` on failure;
- collect pod status and events when the API is reachable.

## Implementation sequence

1. Add and test the four new `ard_images` definitions. Initial definitions have been added in `ansible/roles/ard_provider_common/defaults/main.yml`.
2. Add a MicroShift render preset or scenario that selects `centos-stream-10`. Initial `microshift-single-node` topology and `microshift-node` flavor have been added.
3. Create a clean RPM-first MicroShift playbook/role path. Initial `microshift_*` roles and `ansible/playbooks/workloads/microshift/deploy.yaml` have been added.
4. Validate `make render`, `make apply`, and MicroShift deployment on CentOS Stream 10. Render and syntax checks have been run; full libvirt deployment remains to be run.
5. Add Fedora ELN, AlmaLinux 10, and Rocky Linux 10 smoke scenarios.
6. Add bootc mode after RPM mode is stable.
7. Retire or quarantine old `ensure_microshift` behavior once the new path is equivalent or better.

## Open questions

None currently; remaining work is implementation validation.
