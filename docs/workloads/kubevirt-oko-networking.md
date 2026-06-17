# KubeVirt OKO networking quick reference

The detailed ARD overlay model and KubeVirt OKO packet paths are documented in
[../architecture/network-overlays.md](../architecture/network-overlays.md).

This page is a short scenario-focused checklist for `molecule/kubevirt-oko`.

## Scenario layers

```text
KubeVirt Multus datacenter underlay: 10.0.100.0/24
        |
        v
ARD ospbr/GRETAP overlay: 172.24.4.0/23 bridge mesh
        |
        v
OKO ctlplane and VIPs: 192.168.122.0/24
        |
        v
EDPM br-ex connected to ospbr by oko-br-ex <-> oko-ospbr veth
```

Important rules:

- Keep the KubeVirt datacenter NIC as the GRETAP underlay.
- Do not enslave the datacenter NIC into `ospbr` for KubeVirt OKO.
- EDPM reaches RabbitMQ through the LoadBalancer VIP
  `rabbitmq-cell1.openstack.svc -> 192.168.122.86:5671`.
- MicroShift must have `br_netfilter` loaded and
  `net.bridge.bridge-nf-call-iptables=1` so bridged VIP traffic reaches the
  Kubernetes DNAT rules.
- Site-local proxy names must resolve through DNS. Do not commit private proxy
  hostnames or IP addresses to examples, playbooks, or docs.

## Validation flow

```bash
uv run molecule destroy -s kubevirt-oko
uv run molecule create -s kubevirt-oko
uv run molecule converge -s kubevirt-oko
uv run molecule verify -s kubevirt-oko
```

For iterative work after a successful create:

```bash
uv run molecule converge -s kubevirt-oko
uv run molecule verify -s kubevirt-oko
```

## Fast checks

On an EDPM compute:

```bash
getent ahostsv4 rabbitmq-cell1.openstack.svc
timeout 5 bash -c '</dev/tcp/rabbitmq-cell1.openstack.svc/5671'
ip -br addr show ospbr br-ex oko-ospbr oko-br-ex
systemctl is-active ard-bridge.service
systemctl is-active ard-oko-edpm-uplink.service
```

On MicroShift:

```bash
sysctl net.bridge.bridge-nf-call-iptables
oc --kubeconfig /home/stack/.kube/config -n openstack get svc dnsmasq-dns rabbitmq-cell1-ard-lb -o wide
```
