# ARD Documentation

## Repository index

- [repo-navigation.md](repo-navigation.md) — canonical map of repo structure and workflows
- [concepts/ard-render-model.md](concepts/ard-render-model.md) — user-facing render model and examples guide
- [architecture/](architecture/) — stable design references
  - [ARD_PROVIDER_DESIGN.md](architecture/ARD_PROVIDER_DESIGN.md)
  - [network-overlays.md](architecture/network-overlays.md) — provider networks, ARD bridge overlays, GRETAP, VLANs, and KubeVirt OKO networking
  - [render-contracts.md](architecture/render-contracts.md) — contributor contracts for render inputs, presets, providers, and generated state
- [providers/](providers/) — provider-specific setup notes
  - [kubevirt-prerequisites.md](providers/kubevirt-prerequisites.md) — OpenShift/KubeVirt API, boot-source, SSH, UDN, and instancetype prerequisites
- [workloads/](workloads/) — workload-specific operational notes
  - [kubevirt-oko-networking.md](workloads/kubevirt-oko-networking.md) — quick reference for the `kubevirt-oko` Molecule scenario
- [../examples/](../examples/) — render-file examples with per-directory README files
- [drafts/](drafts/) — work-in-progress reference notes
  - [ARD_OCI_DESIGN.md](drafts/ARD_OCI_DESIGN.md)

## Current implementation status

- Provider reorganization: implemented in the canonical Ansible layout
- Role names: preserved (no role deletions)
- Playbook entry points: canonical paths under `ansible/playbooks/`
