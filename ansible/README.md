# Ansible Layout

This directory is organized as:

- `playbooks/`
  - `provider/` — canonical provider entry points (`render`, `apply`, `deploy-devstack`, `verify`, `destroy`, `cleanup`, `molecule-create`).
  - `providers/{libvirt,kubevirt,static}/` — provider-specific playbook work areas.
  - `workloads/{devstack,microshift,openshift,kind,k8s}/` — workload compositions.
- `roles/` — role library (kept flat for now, no removals).
- `files/` — static data.

## Canonical paths used by workflows

| Workflow | Canonical playbook |
| --- | --- |
| render | `playbooks/provider/render.yaml` |
| apply | `playbooks/provider/apply.yaml` |
| deploy devstack | `playbooks/provider/deploy-devstack.yaml` |
| verify | `playbooks/provider/verify.yaml` |
| destroy | `playbooks/provider/destroy.yaml` |
| cleanup | `playbooks/provider/cleanup.yaml` |

Roles remain named as before (`ard_provider_*`, `ard_libvirt_*`, `devstack_*`, etc.) to avoid breaking dependencies.
