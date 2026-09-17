# OKO examples

These examples render OpenStack Kubernetes Operators (OKO) workloads on top of
MicroShift.

## Examples

- [microshift-two-edpm-compute/](microshift-two-edpm-compute/) - one
  MicroShift node and two EDPM compute nodes. This is the base render file used
  by both the libvirt OKO scenario and the KubeVirt OKO Molecule scenario.
- [remote-libvirt-microshift-two-edpm-compute/](remote-libvirt-microshift-two-edpm-compute/) -
  the same topology and workload manifests executed through a remote libvirt
  host, with deployment state retained on the Ansible controller.

See [../../docs/architecture/network-overlays.md](../../docs/architecture/network-overlays.md)
for the ARD bridge, GRETAP, and KubeVirt OKO networking model.
