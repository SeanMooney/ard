# prepare_operator_dev_tools

Installs operator development tooling on a **RedHat/CentOS MicroShift host**.
This role is the ARD equivalent of the `download_tools` role from
[install_yamls/devsetup](https://github.com/openstack-k8s-operators/install_yamls/tree/main/devsetup),
replicated without any dependency on that project.

It is intended to run before `prepare_operator_sources` to ensure the host
has the build tools required to compile operators and run `make` targets.

## Requirements

- Target host must be a **RedHat family** system (CentOS Stream 9, RHEL 9).
  The role asserts this and fails fast on Debian/Ubuntu hosts.
- Ansible `gather_facts` must be enabled (default).
- `become` privileges are required for Go installation and system packages.

## Tags

Tasks are tag-selectable. Run only the tools you need:

| Tag | What it installs |
|-----|-----------------|
| `dependencies` | System packages via dnf (jq, gcc, make, podman, skopeo, nfs-utils, …) |
| `golang` | Upstream Go tarball to `/usr/local/go`, registered via `update-alternatives` |
| `operator_sdk` | `operator-sdk` binary to `oko_dev_tools_bin_dir` |
| `kustomize` | `kustomize` binary to `oko_dev_tools_bin_dir` |
| `yq` | `yq` binary + symlink to `oko_dev_tools_bin_dir` |
| `kuttl` | `kubectl-kuttl` binary to `oko_dev_tools_bin_dir` |

The `always` tag runs the OS preflight assert and bin directory creation on
every invocation regardless of tag selection.

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `oko_dev_tools_bin_dir` | `{{ ansible_user_dir }}/bin` | Destination for user-local binaries |
| `oko_dev_go_version` | `1.24.6` | Upstream Go release version |
| `oko_dev_sdk_version` | `v1.41.1` | operator-sdk release tag |
| `oko_dev_kustomize_version` | `v5.0.3` | kustomize release tag |
| `oko_dev_kuttl_version` | `0.20.0` | kuttl release version (no leading `v`) |
| `oko_dev_yq_version` | `latest` | yq release tag, or `latest` |
| `oko_dev_tools_packages` | see defaults | Baseline dnf packages to install |
| `oko_dev_tools_packages_extra` | `[]` | Additional dnf packages to install |

## Example Playbook

Install all tools on the MicroShift node:

```yaml
- hosts: microshift
  gather_facts: true
  roles:
    - role: prepare_operator_dev_tools
```

Install only Go and operator-sdk, skipping other tools:

```yaml
- hosts: microshift
  gather_facts: true
  tasks:
    - ansible.builtin.import_role:
        name: prepare_operator_dev_tools
      tags:
        - dependencies
        - golang
        - operator_sdk
```

Override tool versions:

```yaml
- hosts: microshift
  gather_facts: true
  roles:
    - role: prepare_operator_dev_tools
      vars:
        oko_dev_go_version: "1.23.0"
        oko_dev_sdk_version: "v1.38.0"
```

## Notes

- Go is installed system-wide to `/usr/local/go` and registered with
  `update-alternatives` at `/usr/local/bin/go`. After switching from an
  RPM-packaged Go, clear the shell hash cache with `hash -d go`.
- User-local binaries (`operator-sdk`, `kustomize`, `yq`, `kubectl-kuttl`)
  are placed in `oko_dev_tools_bin_dir` (default `~/bin`). Ensure this
  directory is in the target user's `PATH`.

## License

Apache-2.0
