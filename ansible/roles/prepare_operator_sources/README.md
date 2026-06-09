# prepare_operator_sources

Clone or update OpenStack operator source repositories on the MicroShift host
and optionally configure per-repo NFS exports so local checkouts can be mounted
directly into ansibleee pods for pre-merge testing.

Intended to be run against the MicroShift host prior to (or alongside)
`deploy_oko`, so that:

1. Operator Go sources are ready for `make install` + `make run` local testing.
2. Ansible collection sources (e.g. `edpm-ansible`) are NFS-exported and have
   PV/PVC resources applied so `deploy_oko` can inject them into the
   DataPlaneNodeSet `extraMounts`.

## Requirements

- RHEL/CentOS 9+ (MicroShift host only).
- `git` available on the host.
- `oc` available and pointing at the MicroShift cluster (for `render-pv` tasks).
- Go and operator build tools installed — see the `prepare_operator_dev_tools`
  role when `go_prep: true` is used.
- `nfs-utils` is installed automatically when `nfs_export: true` is set for any
  repo.

## Role Variables

### Top-level defaults

| Variable | Default | Description |
|---|---|---|
| `oko_dev_repos_dir` | `/opt/repos` | Base directory for all cloned repos on the MicroShift host. |
| `oko_dev_repos` | `[]` | List of repo entries (see schema below). |
| `oko_dev_nfs_export_options` | `rw,sync,no_root_squash,no_subtree_check` | NFS export options appended to each per-repo export line. |
| `oko_dev_nfs_export_network` | `"*"` | Network/host pattern allowed to mount the NFS export. |
| `oko_dev_nfs_server` | `ansible_host` | IP/hostname of the NFS server (MicroShift node). |
| `oko_dev_namespace` | `openstack` | Kubernetes namespace for PVC resources. |
| `oko_dev_kubeconfig` | `/home/stack/.kube/config` | Kubeconfig used by `oc apply` for PV/PVC creation. |
| `oko_dev_manifest_dir` | `~/ard-oko/dev-sources` | Directory where PV/PVC manifests are rendered before apply. |

### `oko_dev_repos` entry schema

Each list item supports the following keys:

| Key | Required | Default | Description |
|---|---|---|---|
| `name` | yes | — | Directory name created under `oko_dev_repos_dir`. |
| `repo` | yes | — | Git remote URL to clone from. |
| `base_branch` | no | `main` | Branch to track when no `ref` is given. |
| `ref` | no | — | PR ref to fetch and check out, e.g. `pull/1102/head`. Checked out as local branch `pr-under-test`. |
| `go_prep` | no | `false` | When `true`, runs `go mod download` and `make manifests generate` after checkout. Requires Go on PATH. |
| `nfs_export` | no | `false` | When `true`, creates `/etc/exports.d/ard-dev-<name>.exports`, starts `nfs-server`, and renders + applies a PV + PVC. |
| `ansibleee_mount` | no | value of `nfs_export` | When `true`, the `deploy_oko` role injects an `extraMount` for this repo into the `OpenStackDataPlaneNodeSet`. Set explicitly to `false` to export via NFS without mounting in ansibleee. |
| `nfs_mount_path` | no | `/usr/share/ansible/collections/ansible_collections/osp/edpm` | Container path where the PVC is mounted inside ansibleee pods. |
| `nfs_pv_name` | no | `<name>-dev` | Name for the `PersistentVolume` resource. |
| `nfs_pvc_name` | no | `<name>-dev` | Name for the `PersistentVolumeClaim` resource. |

## Example: Testing nova-operator PR #1102 + edpm-ansible PR #1180

This is the primary use-case this role was designed for: testing the Cyborg
controlplane additions in nova-operator alongside the companion edpm-ansible
Cyborg agent role, both before merge.

```yaml
- name: Prepare operator sources for pre-merge Cyborg testing
  hosts: microshift
  roles:
    - role: prepare_operator_sources
      vars:
        oko_dev_repos_dir: /opt/repos
        oko_dev_nfs_server: "{{ ansible_host }}"

        oko_dev_repos:
          # nova-operator PR #1102: Adds Cyborg CRDs and controllers.
          # Operator runs locally on the MicroShift host (no NFS needed).
          - name: nova-operator
            repo: https://github.com/openstack-k8s-operators/nova-operator
            base_branch: main
            ref: pull/1102/head
            go_prep: true
            nfs_export: false

          # edpm-ansible PR #1180: Adds edpm_cyborg role for compute nodes.
          # Exported via NFS and mounted into ansibleee pods at the collection path.
          - name: edpm-ansible
            repo: https://github.com/openstack-k8s-operators/edpm-ansible
            base_branch: main
            ref: pull/1180/head
            go_prep: false
            nfs_export: true
            # ansibleee_mount defaults to true (same as nfs_export)
            nfs_mount_path: /usr/share/ansible/collections/ansible_collections/osp/edpm
```

After the role completes:

### Running the local nova-operator

```bash
cd /opt/repos/nova-operator

# 1. Apply CRDs from the PR checkout to MicroShift
make install

# 2. Scale down the OLM-managed nova operator
#    (See dev-docs/running_local_operator.md for the full procedure)
oc patch csv -n openstack-operators <openstack-operator-csv> --type json \
  -p='[{"op":"replace","path":"/spec/install/spec/deployments/0/spec/replicas","value":"0"}]'
oc patch deployment -n openstack-operators nova-operator-controller-manager --type json \
  -p='[{"op":"replace","path":"/spec/replicas","value":"0"}]'

# 3. Run the operator locally with Cyborg enabled and webhooks disabled
ENABLE_CYBORG=true ENABLE_WEBHOOKS=false GOWORK= OPERATOR_TEMPLATES=./templates make run
```

### Activating the edpm-ansible NFS mount

The `deploy_oko` role reads `oko_dev_repos` and automatically injects
`extraMounts` into the `OpenStackDataPlaneNodeSet` for any entry where
`ansibleee_mount` is `true`. Re-run (or run for the first time) the `deploy_oko`
role with the same `oko_dev_repos` variable to wire the PVC mount:

```yaml
# In your deploy_oko variable file or group_vars:
oko_dev_repos:
  - name: edpm-ansible
    nfs_export: true
    # ansibleee_mount: true  # implied
    nfs_mount_path: /usr/share/ansible/collections/ansible_collections/osp/edpm
    nfs_pvc_name: edpm-ansible-dev
```

The rendered `OpenStackDataPlaneNodeSet` will include:

```yaml
spec:
  nodeTemplate:
    extraMounts:
      - extraVolType: edpm-ansible-dev
        volumes:
        - name: edpm-ansible-dev
          persistentVolumeClaim:
            claimName: edpm-ansible-dev
            readOnly: true
        mounts:
        - name: edpm-ansible-dev
          mountPath: /usr/share/ansible/collections/ansible_collections/osp/edpm
          readOnly: true
```

## Integration with `deploy_oko`

The `deploy_oko` role renders `dataplane.yaml.j2` and, when `oko_dev_repos`
contains entries with `ansibleee_mount: true` (or `nfs_export: true`), it
injects the corresponding `extraMounts` block into the `OpenStackDataPlaneNodeSet`.

Both roles share the same `oko_dev_repos` variable — define it once in your
group vars or playbook and pass it to both roles.

## File layout created on the MicroShift host

```
/opt/repos/
├── nova-operator/          # PR #1102 checked out as branch pr-under-test
└── edpm-ansible/           # PR #1180 checked out as branch pr-under-test

/etc/exports.d/
└── ard-dev-edpm-ansible.exports

~/ard-oko/dev-sources/
└── edpm-ansible-pv.yaml    # PV + PVC manifest (applied to MicroShift)
```
