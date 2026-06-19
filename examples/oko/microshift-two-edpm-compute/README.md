# OKO MicroShift with two EDPM computes

Renders a three-node OKO topology: one MicroShift node and two EDPM compute
nodes.

## Render file

```yaml
ard_provider: libvirt
ard_provider_profile: local-libvirt
ard_topology: oko-microshift-two-compute
ard_service_profiles: []
```

The render file defaults to libvirt. Molecule scenarios can reuse it and
override the provider. For example, `molecule/kubevirt-oko` uses this render
file with the KubeVirt provider and datacenter networking enabled.

## Topology

```text
+------------+        +----------------+        +----------------+
| microshift |        | edpm-compute-1 |        | edpm-compute-2 |
|            |        |                |        |                |
| OKO        |        | EDPM compute   |        | EDPM compute   |
| bridge     |<------>| bridge peer    |<------>| bridge peer    |
| switch     |        |                |        |                |
+------------+        +----------------+        +----------------+
```

The MicroShift node is in the `switch` group for the ARD multinode bridge.
The EDPM nodes are bridge peers. The bridge can carry the OpenStack ctlplane
and network-isolation VLANs.

For KubeVirt-specific details, including the OVN-K UserDefinedNetwork
datacenter underlay, GRETAP overlay, EDPM veth uplink, and LoadBalancer VIP
path, see
[../../../docs/architecture/network-overlays.md](../../../docs/architecture/network-overlays.md).
