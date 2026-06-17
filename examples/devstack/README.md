# DevStack examples

These examples render libvirt-based DevStack deployments. They all use the
`local-libvirt` provider profile and enable the `devstack`, `ovn`, and
`tempest` service profiles.

## Examples

- [all-in-one/](all-in-one/) - one controller VM that also runs compute.
- [aio-plus-compute/](aio-plus-compute/) - one all-in-one controller plus one
  additional compute VM. The render file uses the historical
  `one-controller-one-compute` topology alias.
- [one-controller-two-compute/](one-controller-two-compute/) - one controller
  VM and two compute VMs.
- [centos-10-one-controller-two-compute/](centos-10-one-controller-two-compute/) -
  one controller VM and two compute VMs using the CentOS Stream 10 image.

## Usage

```bash
uv run ansible-playbook ansible/playbooks/provider/render.yaml \
  -e @examples/devstack/<example>/render.yaml \
  -e ard_deployment_dir=$PWD/deployments/<name>
```

Then apply the rendered provider resources and run the DevStack workload
playbooks appropriate for the deployment.
