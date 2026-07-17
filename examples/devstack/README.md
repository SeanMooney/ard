# DevStack examples

These examples render DevStack deployments for managed libvirt VMs or
pre-provisioned static hosts. They enable the `devstack`, `ovn`, and `tempest`
service profiles unless an example says otherwise.

## Examples

- [all-in-one/](all-in-one/) - one controller VM that also runs compute.
- [aio-plus-compute/](aio-plus-compute/) - one all-in-one controller plus one
  additional compute VM. The render file uses the historical
  `one-controller-one-compute` topology alias.
- [one-controller-two-compute/](one-controller-two-compute/) - one controller
  VM and two compute VMs.
- [centos-10-one-controller-two-compute/](centos-10-one-controller-two-compute/) -
  one controller VM and two compute VMs using the CentOS Stream 10 image.
- [static-cyborg-pci-sim/](static-cyborg-pci-sim/) - one pre-provisioned
  CentOS Stream 10 AIO host with Cyborg and the pci-sim kernel module.

## Usage

```bash
make render \
  ARD_DEPLOYMENT=<name> \
  ARD_RENDER_FILE=examples/devstack/<example>/render.yaml
make apply ARD_DEPLOYMENT=<name>
make deploy ARD_DEPLOYMENT=<name>
```

Read the selected example's README for provider prerequisites and validation
steps.
