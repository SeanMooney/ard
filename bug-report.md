# RabbitMq override.service.spec.loadBalancerClass is not propagated to Service

## Summary

`RabbitMq.spec.override.service.spec.loadBalancerClass` is accepted by the CRD and preserved on the `RabbitMq` custom resource, but the generated Kubernetes `Service` does not include `spec.loadBalancerClass`.

This breaks deployments on MicroShift where the built-in MicroShift LoadBalancer service controller updates unclassed `Service type=LoadBalancer` objects with the node IP. In an OpenStack K8s Operators deployment using MetalLB, that causes the RabbitMQ service status to use the MicroShift node IP instead of the requested MetalLB VIP.

## Environment

- Project: OpenStack K8s Operators on MicroShift
- CNI: OVN-Kubernetes, with Multus for secondary networks
- LoadBalancer implementation: MetalLB
- MicroShift node IP: `192.168.102.2`
- MetalLB ctlplane VIPs:
  - internal APIs: `192.168.122.80`
  - dnsmasq: `192.168.122.81`
  - rabbitmq: `192.168.122.85`
  - rabbitmq-cell1: `192.168.122.86`
- MetalLB configured with:
  - controller arg: `--lb-class=metallb.io/metallb`
  - speaker arg: `--lb-class=metallb.io/metallb`

## Reproducer

Configure the OpenStackControlPlane RabbitMQ templates with a service override containing both MetalLB annotations and `loadBalancerClass`:

```yaml
spec:
  rabbitmq:
    templates:
      rabbitmq:
        override:
          service:
            metadata:
              annotations:
                metallb.universe.tf/address-pool: ctlplane
                metallb.universe.tf/loadBalancerIPs: 192.168.122.85
            spec:
              type: LoadBalancer
              loadBalancerClass: metallb.io/metallb
      rabbitmq-cell1:
        override:
          service:
            metadata:
              annotations:
                metallb.universe.tf/address-pool: ctlplane
                metallb.universe.tf/loadBalancerIPs: 192.168.122.86
            spec:
              type: LoadBalancer
              loadBalancerClass: metallb.io/metallb
```

After reconciliation, the generated `RabbitMq` CRs contain the class:

```yaml
apiVersion: rabbitmq.openstack.org/v1beta1
kind: RabbitMq
metadata:
  name: rabbitmq
spec:
  override:
    service:
      metadata:
        annotations:
          metallb.universe.tf/address-pool: ctlplane
          metallb.universe.tf/loadBalancerIPs: 192.168.122.85
      spec:
        loadBalancerClass: metallb.io/metallb
        type: LoadBalancer
```

But the generated Services do not:

```text
$ oc -n openstack get svc rabbitmq rabbitmq-cell1 \
  -o jsonpath='{range .items[*]}{.metadata.name} class={.spec.loadBalancerClass} status={.status.loadBalancer.ingress[*].ip}{"\n"}{end}'
rabbitmq class= status=192.168.102.2
rabbitmq-cell1 class= status=
```

## Expected result

The generated RabbitMQ client Services should include the requested class:

```yaml
spec:
  type: LoadBalancer
  loadBalancerClass: metallb.io/metallb
```

Then MicroShift's built-in LoadBalancer service controller ignores them, and MetalLB owns `status.loadBalancer`.

## Actual result

The Services are created without `spec.loadBalancerClass`.

On MicroShift, the built-in LoadBalancer controller handles unclassed services and writes the MicroShift node IP into status:

```text
rabbitmq status=192.168.102.2
```

`rabbitmq-cell1` can remain pending because the built-in controller cannot expose another same-port RabbitMQ LoadBalancer service on the same node IP.

This also pollutes operator-generated DNS data:

```yaml
spec:
  hosts:
  - ip: 192.168.102.2
    hostnames:
    - rabbitmq.openstack.svc
```

EDPM nodes must not consume the MicroShift node IP for RabbitMQ; they need the ctlplane MetalLB VIP.

## Why this appears to be a bug

`lib-common/modules/common/service.OverrideSpec` supports `loadBalancerClass`:

```go
type OverrideServiceSpec struct {
    // ...
    LoadBalancerClass *string `json:"loadBalancerClass,omitempty" protobuf:"bytes,21,opt,name=loadBalancerClass"`
    // ...
}
```

The RabbitMQ CRD exposes this field under:

```text
RabbitMq.spec.override.service.spec.loadBalancerClass
```

However, the RabbitMQ service renderer appears to manually copy only selected override fields.

In `infra-operator` `upstream/main:internal/rabbitmq/service.go`, the helper functions include:

```go
func serviceOverrideType(r *rabbitmqv1.RabbitMq) corev1.ServiceType {
    if r.Spec.Override.Service != nil && r.Spec.Override.Service.Spec != nil {
        return r.Spec.Override.Service.Spec.Type
    }
    return ""
}

func serviceOverrideIPFamilyPolicy(r *rabbitmqv1.RabbitMq) *corev1.IPFamilyPolicy {
    if r.Spec.Override.Service != nil && r.Spec.Override.Service.Spec != nil {
        return r.Spec.Override.Service.Spec.IPFamilyPolicy
    }
    return nil
}
```

`ClientService()` then applies service type, annotations, and IP family policy, but does not copy:

```go
r.Spec.Override.Service.Spec.LoadBalancerClass
```

## Suggested fix

Propagate `LoadBalancerClass` from the service override to the generated client Service, for example by adding a helper similar to `serviceOverrideIPFamilyPolicy()` and setting:

```go
if lbClass := serviceOverrideLoadBalancerClass(r); lbClass != nil {
    svc.Spec.LoadBalancerClass = lbClass
}
```

This must happen at Service creation time because Kubernetes treats `spec.loadBalancerClass` as immutable after creation.

## Annotation alternative

There does not appear to be a Kubernetes annotation equivalent for `spec.loadBalancerClass`.

MicroShift's built-in LoadBalancer controller ignores only Services whose `spec.loadBalancerClass` is non-nil. It does not check annotations for this behavior. Therefore, using annotations instead of `spec.loadBalancerClass` will not prevent MicroShift from reconciling RabbitMQ LoadBalancer Services.

MetalLB annotations such as `metallb.universe.tf/loadBalancerIPs` request an address from MetalLB, but they do not set Kubernetes LoadBalancer ownership/class semantics and do not stop the default/MicroShift LoadBalancer controller from writing status.

## Namespace/default LoadBalancerClass alternative

Kubernetes does not provide a native namespace-level or cluster-level default for `Service.spec.loadBalancerClass` analogous to a default `StorageClass`.

MicroShift's built-in LoadBalancer controller also does not consult namespace annotations or labels. It skips only Services where the spec field is set:

```go
if svc.Spec.Type != corev1.ServiceTypeLoadBalancer || svc.Spec.LoadBalancerClass != nil || isDefaultRouterService(svc) {
    return nil
}
```

Therefore, annotating the `openstack` namespace cannot make MicroShift ignore RabbitMQ LoadBalancer Services.

A mutating admission webhook could default `spec.loadBalancerClass` on newly-created `Service type=LoadBalancer` objects in the `openstack` namespace, but that is additional cluster machinery and must run before Service creation because `spec.loadBalancerClass` is immutable after creation.

The tested MicroShift cluster exposes `ValidatingAdmissionPolicy`, but not `MutatingAdmissionPolicy`, so a built-in policy-only defaulting workaround is not available in this environment.
