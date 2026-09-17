# Remote-libvirt MicroShift with two EDPM computes

This example runs the existing MicroShift and two-EDPM OKO topology on a
remote libvirt execution host. Its
[`render.yaml`](render.yaml) uses the same workload topology as the base
[`microshift-two-edpm-compute`](../microshift-two-edpm-compute/) example; only
provider execution changes. Native Ansible SSH delegation runs libvirt
operations against execution-host-local `qemu:///system`; this does not use a
`qemu+ssh` URI. Deployment state and rendered manifests remain on the Ansible
controller, while VM disks, seed media, and console logs live on the execution
host. Workload preparation and Kubernetes
operations run on the created VMs, never on the execution host.

## Prerequisites

The execution host must be reachable through an OpenSSH host alias, provide
passwordless privilege escalation, and support nested KVM. Prepare it separately
when needed:

```bash
uv run ansible-playbook \
  -i virt-host, \
  ansible/playbooks/provider/bootstrap-libvirt-host.yaml \
  -e ard_libvirt_bootstrap_user=stack
```

## Render and configure

Change the example management CIDR in `render.yaml` if it overlaps a network
on the execution host, then render the deployment:

```bash
make render \
  ARD_DEPLOYMENT=remote-libvirt-oko \
  ARD_RENDER_FILE=examples/oko/remote-libvirt-microshift-two-edpm-compute/render.yaml
```

Rendering copies `local-vars.yaml.example` to deployment-local
`local-vars.yaml` without overwriting an existing file. Uncomment the execution
host settings there and replace `virt-host` with the required OpenSSH alias
before running `make apply`. Leaving the block commented selects local libvirt.
Keep credentials and private-key contents out of reusable example and
deployment variable files.

## Deploy and validate

Use the same lifecycle as a local-libvirt OKO deployment:

```bash
make apply ARD_DEPLOYMENT=remote-libvirt-oko
make ping ARD_DEPLOYMENT=remote-libvirt-oko
make deploy ARD_DEPLOYMENT=remote-libvirt-oko
make verify ARD_DEPLOYMENT=remote-libvirt-oko
```

Inspect the cluster and follow dataplane jobs as the unprivileged `stack` user:

```bash
make ssh ARD_DEPLOYMENT=remote-libvirt-oko ARD_NODE=microshift
oc get openstackcontrolplane,openstackdataplanenodeset,openstackdataplanedeployment \
  -n openstack
~/ard-oko/monitor-dataplane-jobs.sh
```

The direct-libvirt dataplane attaches each EDPM node's second NIC to OVS
`br-ex`. This differs from the KubeVirt variant, which retains its datacenter
underlay and connects the ARD bridge through a veth pair. Both paths use the
same OKO workload manifests and topology.

## Cleanup

Remove only the resources recorded as owned by this deployment:

```bash
make destroy-clean-generated ARD_DEPLOYMENT=remote-libvirt-oko
```
