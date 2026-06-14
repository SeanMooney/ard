# ARD Documentation

## Repository index

- [repo-navigation.md](repo-navigation.md) — canonical map of repo structure and workflows
- [concepts/ard-render-model.md](concepts/ard-render-model.md) — user-facing render model and examples guide
- [architecture/](architecture/) — stable design references
  - [ARD_PROVIDER_DESIGN.md](architecture/ARD_PROVIDER_DESIGN.md)
  - [render-contracts.md](architecture/render-contracts.md) — contributor contracts for render inputs, presets, providers, and generated state
- [drafts/](drafts/) — work-in-progress reference notes
  - [ARD_OCI_DESIGN.md](drafts/ARD_OCI_DESIGN.md)

## Current implementation status

- Provider reorganization: implemented in the canonical Ansible layout
- Role names: preserved (no role deletions)
- Playbook entry points: canonical paths under `ansible/playbooks/`
