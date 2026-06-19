# ARD network overlays

ARD separates provider networking from workload networking. Provider networks
make the virtual machines reachable. Workload overlays are created inside the
VMs when a scenario needs multi-node service networks that are independent of
the provider implementation.

This document describes the common model and then calls out the KubeVirt OKO
variant that uses an OVN-Kubernetes UserDefinedNetwork datacenter underlay plus
an ARD GRETAP overlay.

## Common network layers

```text
+-----------------------------------------------------------------------+
| Provider layer                                                        |
|                                                                       |
|  libvirt network, KubeVirt pod network, KubeVirt UDN attachment,      |
|  or another provider-specific network created by provider roles       |
+-----------------------------------------------------------------------+
                 |                          |
                 v                          v
+------------------------------+   +------------------------------+
| VM: controller/microshift    |   | VM: compute/EDPM peer        |
|                              |   |                              |
| management NIC               |   | management NIC               |
| workload/datacenter NIC      |   | workload/datacenter NIC      |
| workload bridges and VLANs   |   | workload bridges and VLANs   |
+------------------------------+   +------------------------------+
```

The provider layer should answer only the question "how do the VMs get
created and reached?". Workload overlays answer "how do services inside those
VMs communicate?".

## Management network

Every rendered deployment has a management path used by SSH and Ansible. The
exact implementation is provider-specific:

- libvirt scenarios normally use a libvirt NAT network.
- KubeVirt scenarios use the provider inventory address produced by the
  KubeVirt inventory role.

Workloads should not assume that the management interface is also the OpenStack
provider, ctlplane, or tenant interface.

## Datacenter underlay

Some topologies add a second provider network named `datacenter`. This is a
plain VM-to-VM transport network. It is not automatically the workload bridge;
it is the underlay on top of which a workload can build more specific network
state.

```text
          datacenter provider network
   ------------------------------------------
      VM A NIC        VM B NIC        VM C NIC
```

For KubeVirt, this network is currently backed by an OVN-Kubernetes
`UserDefinedNetwork` with Layer2 topology and IPAM disabled. In the OKO
KubeVirt topology it commonly uses `10.0.100.0/24`. Those addresses are GRETAP
endpoints, not OpenStack ctlplane addresses.

The KubeVirt datacenter network therefore requires an OpenShift cluster using
OVN-Kubernetes with the `k8s.ovn.org/v1` `UserDefinedNetwork` API available.
It is not a generic host-local bridge NetworkAttachmentDefinition.

## ARD multinode bridge overlay

The `ard_multinode_bridge` role creates a Linux bridge on each participating
VM and connects the bridges with GRETAP tunnels. One node is the switch/hub and
other nodes are peers.

```text
                    GRETAP mesh over provider/datacenter underlay

                  +------------------ switch ------------------+
                  |                                            |
                  v                                            v
+------------------------+        +------------------------+  +------------------------+
| peer VM                |        | switch VM              |  | peer VM                |
|                        |        |                        |  |                        |
| datacenter: 10.0.100.2 |<------>| datacenter: 10.0.100.1 |<>| datacenter: 10.0.100.3 |
| gretap tunnel port     |        | gretap tunnel ports    |  | gretap tunnel port     |
| ospbr                  |        | ospbr                  |  | ospbr                  |
+------------------------+        +------------------------+  +------------------------+
```

The bridge is workload-owned state. It may carry:

- an ARD bridge-mesh address such as `172.24.4.x/23`;
- an OpenStack ctlplane subnet such as `192.168.122.0/24`;
- VLAN subinterfaces such as `ospbr.20`, `ospbr.21`, and `ospbr.22`.

Because workloads can attach extra state to the bridge, `ard-bridge.service`
removes tunnel ports on stop but leaves the bridge itself intact.

## VLAN overlays

Workloads that need network isolation can create VLAN interfaces on top of the
Linux bridge:

```text
ospbr
  |-- untagged ctlplane       192.168.122.0/24
  |-- ospbr.20 internalapi    172.17.0.0/24
  |-- ospbr.21 storage        172.18.0.0/24
  `-- ospbr.22 tenant         172.19.0.0/24
```

The VLANs remain inside the VM overlay. The provider only carries the GRETAP
underlay packets.

## KubeVirt OKO topology

`kubevirt-oko` combines the layers above:

```text
                         KubeVirt namespace

        OVN-K UDN datacenter underlay: 10.0.100.0/24
   -----------------------------------------------------------------
          | 10.0.100.1              | 10.0.100.2       | 10.0.100.3
          |                         |                  |
   +---------------+          +---------------+  +---------------+
   | MicroShift VM |          | EDPM compute1 |  | EDPM compute2 |
   |               |          |               |  |               |
   | datacenter NIC|          | datacenter NIC|  | datacenter NIC|
   |      |        |          |      |        |  |      |        |
   |      | GRETAP |<-------->| GRETAP       |  | GRETAP       |
   |      v        |          |      v        |  |      v        |
   |    ospbr      |<========>|    ospbr      |<>|    ospbr      |
   | 192.168.122.2| overlay  | 172.24.4.2   |  | 172.24.4.3   |
   | 172.24.4.1   |          |      |        |  |      |        |
   |      |        |          | oko-ospbr     |  | oko-ospbr     |
   |  OKO pods,   |          |      | veth   |  |      | veth   |
   |  services,   |          | oko-br-ex     |  | oko-br-ex     |
   |  MetalLB VIPs|          |      |        |  |      |        |
   |              |          |    br-ex      |  |    br-ex      |
   |              |          |192.168.122.100|  |192.168.122.101|
   +---------------+          +---------------+  +---------------+
```

The MicroShift node is the ARD bridge switch. EDPM computes are peers. OKO
service VIPs live on the ctlplane overlay, not on the KubeVirt datacenter
underlay.

### Why the datacenter NIC stays separate

In a libvirt OKO topology, a dedicated provider NIC can be enslaved directly
into the OKO ctlplane bridge. In KubeVirt OKO, the datacenter NIC is the GRETAP
underlay. Moving it into `ospbr` collapses the underlay and overlay together.

For KubeVirt OKO:

```yaml
oko_manage_ctlplane_bridge_slave: false
```

This means:

- `pre-multinode.yaml` creates `ospbr` and GRETAP tunnels.
- OKO reuses the pre-created `ospbr` bridge.
- the datacenter NIC keeps the `10.0.100.x` underlay address.
- `ospbr` carries ctlplane and VLAN overlays.

### EDPM bridge wiring

EDPM expects OpenStack public/ctlplane traffic on OVS `br-ex`. The ARD overlay
uses Linux bridge `ospbr`. KubeVirt OKO connects them with a veth pair after
os-net-config creates `br-ex`.

```text
EDPM compute node

       ARD overlay bridge                 OVS dataplane bridge
   +----------------------+             +----------------------+
   | ospbr                |             | br-ex                |
   | 172.24.4.x/23        |             | 192.168.122.10x/24  |
   | GRETAP tunnel port   |             | VLANs via EDPM cfg  |
   |                      |             |                      |
   |  oko-ospbr <=====================> oko-br-ex              |
   |     Linux end       veth pair       OVS end               |
   +----------------------+             +----------------------+
```

The helper service is `ard-oko-edpm-uplink.service`. It waits for `ospbr` and
`br-ex`, waits for os-net-config to finish, restarts `ard-bridge.service`, and
then wires the veth pair.

### LoadBalancer VIP path

OKO services are exposed to EDPM through MetalLB LoadBalancer VIPs on the
ctlplane overlay. For example:

```text
rabbitmq-cell1.openstack.svc -> 192.168.122.86:5671
```

Expected packet path:

```text
nova-compute container
        |
        v
EDPM br-ex: 192.168.122.100
        |
        v
oko-br-ex <== veth ==> oko-ospbr
        |
        v
EDPM ospbr
        |
        v
GRETAP over 10.0.100.0/24 datacenter underlay
        |
        v
MicroShift ospbr receives packet for 192.168.122.86:5671
        |
        v
bridge netfilter passes bridged packet to iptables/nft rules
        |
        v
OVN/kube-proxy DNAT to RabbitMQ service/pod
        |
        v
rabbitmq-cell1-server-0:5671
```

`br_netfilter` and `net.bridge.bridge-nf-call-iptables=1` are required on the
MicroShift node. Without them, ARP for the VIP can succeed while TCP to the
same VIP times out because bridged packets bypass Kubernetes DNAT rules.

### DNS and proxy expectations

EDPM nodes use the OKO dnsmasq LoadBalancer VIP as their resolver:

```text
nameserver 192.168.122.81
```

The OKO dnsmasq service serves OpenStack service names and forwards other names
to MicroShift DNS. External or site-local proxy hostnames must resolve through
DNS. Playbooks must not add private site-specific proxy hostnames or addresses
to `/etc/hosts`.

Use a locally supplied `local-vars.yaml` for proxy values when required by the
site. Do not commit site-specific proxy hostnames or IP addresses.

## MTU model

Provider underlays may expose guest NICs with an MTU below 1500. KubeVirt
secondary network attachments commonly use a lower MTU than a default Ethernet
link. The OKO KubeVirt scenario therefore uses a conservative MTU:

```yaml
oko_network_mtu: 1300
oko_ctlplane_mtu: 1300
oko_vlan_network_mtu: 1296
```

The VLAN networks subtract four bytes from the base MTU. This leaves room for
provider and GRETAP encapsulation overhead while keeping OKO and EDPM network
configuration consistent.

## Troubleshooting commands

On an EDPM compute:

```bash
cat /etc/resolv.conf
ip route
ip -br addr show ospbr br-ex oko-ospbr oko-br-ex
systemctl status ard-bridge.service
systemctl status ard-oko-edpm-uplink.service
journalctl -u ard-bridge.service -u ard-oko-edpm-uplink.service --no-pager -n 100
ovs-vsctl show
getent ahostsv4 rabbitmq-cell1.openstack.svc
timeout 5 bash -c '</dev/tcp/rabbitmq-cell1.openstack.svc/5671'
podman logs --tail=100 nova_compute
```

On the MicroShift node:

```bash
ip -br addr show ospbr
sysctl net.bridge.bridge-nf-call-iptables
oc --kubeconfig /home/stack/.kube/config -n openstack get svc dnsmasq-dns rabbitmq-ard-lb rabbitmq-cell1-ard-lb -o wide
oc --kubeconfig /home/stack/.kube/config -n openstack get dnsdata -o yaml
oc --kubeconfig /home/stack/.kube/config -n openstack get endpoints rabbitmq-cell1 rabbitmq-cell1-ard-lb -o yaml
oc --kubeconfig /home/stack/.kube/config -n openstack exec rabbitmq-cell1-server-0 -- rabbitmq-diagnostics listeners
```

Packet captures:

```bash
# EDPM
tcpdump -i any -nn host 192.168.122.81 or host 192.168.122.86

# MicroShift
tcpdump -i any -nn 'host 192.168.122.100 and (port 53 or port 5671 or arp)'
```

Interpretation hints:

- DNS queries arrive at MicroShift but there are no replies: inspect
  `dnsmasq-dns` and DNSData.
- ARP for a VIP succeeds but TCP times out: check `br_netfilter` and
  `net.bridge.bridge-nf-call-iptables` on MicroShift.
- TCP to RabbitMQ works but nova-compute still logs AMQP errors: inspect the
  rendered `transport_url`, TLS settings, and nova-compute container logs.
