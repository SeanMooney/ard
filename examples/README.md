# ARD examples

This directory contains render-file examples. A render file is the small YAML
input that tells ARD which provider, provider profile, topology, workload, and
service profiles to render.

Typical flow:

```bash
make render \
  ARD_DEPLOYMENT=<name> \
  ARD_RENDER_FILE=examples/<category>/<example>/render.yaml
make apply ARD_DEPLOYMENT=<name>
```

Some Molecule scenarios use these files through `provisioner.ard_render_file`.
For example, `molecule/kubevirt-oko` reuses
`examples/oko/microshift-two-edpm-compute/render.yaml` and overrides the
provider to KubeVirt from its scenario config.

## Categories

- [devstack/](devstack/) - DevStack workload examples.
- [microshift/](microshift/) - MicroShift workload examples.
- [oko/](oko/) - OpenStack Kubernetes Operators on MicroShift examples.
- [provider-test/](provider-test/) - provider-only smoke examples.

## Notes

- Do not commit local proxy hostnames, internal IP addresses, credentials, or
  site-specific overrides in example render files.
- Put site-specific values in an ignored `local-vars.yaml` or pass them with
  `-e` at runtime.
- See [../docs/architecture/network-overlays.md](../docs/architecture/network-overlays.md)
  for the common ARD network overlay model.
- See [../docs/providers/kubevirt-prerequisites.md](../docs/providers/kubevirt-prerequisites.md)
  before running KubeVirt examples or Molecule scenarios.
