# KubeVirt provider prerequisites

The ARD KubeVirt provider targets a generic OpenShift cluster with OpenShift
Virtualization installed. It should not depend on a specific cluster or
namespace, but the cluster must provide the APIs and resources listed here.

## OpenShift access

Log in with `oc` and select the target project before running KubeVirt
scenarios:

```bash
oc login <cluster-api>
oc project <target-namespace>
```

Molecule KubeVirt scenarios use the current project from:

```bash
oc project --short
```

Direct Make runs can use the same current project or an explicit override:

```bash
make render ARD_PROVIDER=kubevirt ARD_KUBEVIRT_NAMESPACE=$(oc project --short)
```

The selected namespace must already exist unless a future workflow explicitly
creates it. The current provider expects permissions to create, update, and
delete these resources in that namespace:

- `VirtualMachine` and `VirtualMachineInstance`
- `DataVolume` and backing PVCs
- `Service` resources used for SSH access
- `Secret` resources for SSH public keys
- `UserDefinedNetwork` when the datacenter network is enabled

## Required APIs

The cluster must provide:

- KubeVirt / OpenShift Virtualization APIs (`kubevirt.io`)
- CDI APIs (`cdi.kubevirt.io`) for `DataVolume` cloning from boot sources
- OVN-Kubernetes `UserDefinedNetwork` APIs (`k8s.ovn.org/v1`) when using
  `ard_kubevirt_datacenter_network: true`

The datacenter network implementation is an OVN-Kubernetes `UserDefinedNetwork`
with Layer2 topology and IPAM disabled. It is not a host-local Linux bridge
NetworkAttachmentDefinition. Disable the datacenter network for scenarios that
do not need a secondary network:

```yaml
ard_kubevirt_datacenter_network: false
```

## SSH access

The current implementation exposes the controller VM SSH port through a
Kubernetes `LoadBalancer` Service and reaches other VMs through the controller
as an SSH jump host.

The cluster therefore needs a working LoadBalancer implementation, for example
MetalLB or a cloud-provider LoadBalancer. `ard_kubevirt_ssh_access` currently
defaults to `loadbalancer`; other modes are design placeholders until they are
implemented.

ARD creates a public-key Secret named by `ard_kubevirt_ssh_key_secret`, which
defaults to:

```yaml
ard_kubevirt_ssh_key_secret: "{{ ard_user }}-pub-key"
```

The private key defaults to:

```yaml
ard_kubevirt_ssh_private_key_file: ~/.ssh/id_ed25519_stack
```

Override these variables if your environment uses a different key or naming
policy.

## VM boot sources

KubeVirt VM disks are cloned from CDI `DataSource` boot sources. The default
image map expects these sources:

| ARD image | Expected KubeVirt DataSource |
| --- | --- |
| `debian-13` | `DataSource/debian-13` in the target namespace |
| `ubuntu-24.04` | `DataSource/ubuntu-24.04` in the target namespace |
| `centos-stream-9` | `DataSource/centos-stream9` in `openshift-virtualization-os-images` |
| `centos-stream-10` | `DataSource/centos-stream10` in `openshift-virtualization-os-images` |

The CentOS Stream entries use the standard OpenShift Virtualization boot-source
namespace. If your cluster does not enable those boot sources, create equivalent
DataSources or override the image mapping before rendering.

## Instancetypes and preferences

The default KubeVirt flavor mapping references namespace-local resources:

- `VirtualMachineInstancetype/devstack-8c16g`
- `VirtualMachineInstancetype/devstack-8c8g`
- `VirtualMachineInstancetype/devstack-2c1g`
- `VirtualMachinePreference/devstack`

Install or update the bundled defaults in the selected namespace with:

```bash
make kubevirt-resources ARD_KUBEVIRT_NAMESPACE=$(oc project --short)
```

The provider preflight checks for these resources and the selected boot source
before creating VMs.

## KubeVirt OKO networking

The `kubevirt-oko` scenario additionally depends on the ARD GRETAP overlay and
OKO LoadBalancer VIP path documented in:

- [../architecture/network-overlays.md](../architecture/network-overlays.md)
- [../workloads/kubevirt-oko-networking.md](../workloads/kubevirt-oko-networking.md)

The short version is:

- `10.0.100.0/24` is the KubeVirt datacenter underlay used for GRETAP endpoints.
- `192.168.122.0/24` is the OKO ctlplane overlay carried on `ospbr`/`br-ex`.
- The KubeVirt datacenter NIC must not be enslaved into `ospbr` for the KubeVirt
  OKO topology.
- MicroShift must load `br_netfilter` and set
  `net.bridge.bridge-nf-call-iptables=1` so bridged EDPM traffic to OKO
  LoadBalancer VIPs reaches Kubernetes DNAT rules.
