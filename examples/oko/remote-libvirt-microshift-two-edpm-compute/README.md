# Remote-libvirt MicroShift with two EDPM computes

This example runs the existing MicroShift and two-EDPM OKO topology on a
remote libvirt execution host. It intentionally reuses the base workload render
intent unchanged:

[`../microshift-two-edpm-compute/render.yaml`](../microshift-two-edpm-compute/render.yaml)

Only provider execution changes. Deployment state and rendered manifests remain
on the Ansible controller, while libvirt operations, VM disks, seed media, and
console logs live on the execution host. Workload preparation and Kubernetes
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

Choose an unused management CIDR:

```bash
make render \
  ARD_DEPLOYMENT=remote-libvirt-oko \
  ARD_RENDER_FILE=examples/oko/microshift-two-edpm-compute/render.yaml \
  ARD_NETWORK_CIDR=192.168.119.0/24
```

The command-line CIDR applies to that render invocation. Persist it before
later plain `make render` calls by setting it in the copied deployment intent:

```yaml
# deployments/remote-libvirt-oko/render.yaml
ard_libvirt_network_cidr: 192.168.119.0/24
```

Create `deployments/remote-libvirt-oko/local-vars.yaml` with site-local
execution details. Do not put host aliases or credentials in the reusable
example:

```yaml
---
ard_libvirt_execution_host:
  name: virt-host
  ansible_become: true
ard_libvirt_execution_image_dir: /var/lib/libvirt/images/ard
ard_libvirt_execution_image_cache_dir: /var/lib/libvirt/images/ard/cache
```

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
