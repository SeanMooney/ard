# ARD Repo Navigation

## Top-level

- `README.md` — quick start and command reference
- `Makefile` — canonical workflow entry points
- `bootstrap-repo.sh`, `bindep.txt` — host bootstrap
- `deployments/` — generated deployment workspaces
- `molecule/` — CI/test scenarios
- `submodules/` — external upstream sources
- `ansible/` — all Ansible playbooks, roles, and data
- `docs/` — docs index and design plans

## Ansible layout

- `ansible/playbooks/provider/`
  - `render.yaml`, `apply.yaml`, `deploy-devstack.yaml`, `verify.yaml`, `destroy.yaml`, `cleanup.yaml`, `molecule-create.yaml`
- `ansible/playbooks/workloads/`
  - `devstack/` (`common.yaml`, `controller.yaml`, `compute.yaml`, `vdpa.yaml`, `deploy-multinode.yaml`)
  - `microshift/deploy.yaml`
  - `openshift/deploy-shift-stack.yaml`
  - `kind/` and `k8s/` placeholders
- `ansible/roles/` — reusable roles (preserved)
- `ansible/files/` — static role assets/data

## Top workflow commands

- `make render` -> `ansible/playbooks/provider/render.yaml`
- `make apply` -> `ansible/playbooks/provider/apply.yaml`
- `make deploy` -> `ansible/playbooks/provider/deploy-devstack.yaml`
- `make verify` -> `ansible/playbooks/provider/verify.yaml`
- `make destroy` -> `ansible/playbooks/provider/destroy.yaml`
- `make cleanup` -> `ansible/playbooks/provider/cleanup.yaml`

## First places to check

- **Provider behavior:** `ansible/playbooks/provider/` and `ansible/roles/ard_provider_*`
- **Static provider entry points:** `ansible/roles/ard_static_*`
- **KubeVirt provider placeholder:** not yet documented
- **Workload composition:** `ansible/playbooks/workloads/`
- **Libvirt implementation details:** `ansible/roles/ard_libvirt_*`
