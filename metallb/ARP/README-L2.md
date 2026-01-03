# MetalLB Layer 2 (L2) Configuration Guide

This guide covers the Layer 2 (ARP/NDP) configuration for MetalLB on your Vagrant Kubernetes cluster.

## Overview

Layer 2 mode is the simplest way to configure MetalLB. In this mode, MetalLB responds to ARP requests on the local network, making LoadBalancer IPs appear as if they're directly connected to the local network segment.

### How L2 Mode Works

1. MetalLB assigns an IP from the configured pool to a LoadBalancer service
2. One node becomes the "leader" for that service
3. The leader node responds to ARP requests for the LoadBalancer IP
4. Traffic goes directly to the leader node, which forwards it to the service pods
5. If the leader fails, another node takes over (failover takes ~10 seconds)

### Advantages

- **Simple setup**: No external infrastructure required
- **Works anywhere**: Only requires Layer 2 connectivity
- **No special hardware**: Works with any network equipment
- **Fast deployment**: Ready in seconds

### Limitations

- **Single-node bottleneck**: All traffic goes through one node
- **Network segment only**: Can't route across subnets
- **ARP overhead**: Slight network overhead from ARP responses
- **Failover time**: ~10 seconds during node failure

## Prerequisites

- Kubernetes cluster running on Vagrant
- kubectl configured to access your cluster
- Nodes on the same Layer 2 network (192.168.56.x range)
- IP address range that doesn't conflict with existing nodes

## Configuration Files

### Required Files

```
metallb/
├── metallb-install.yaml         # MetalLB installation manifest
├── ipaddresspool.yaml           # IP address pool configuration
├── ARP/l2advertisement.yaml         # L2 advertisement configuration
├── nginx-deployment.yaml        # Test application (optional)
└── loadbalancer-service.yaml    # LoadBalancer service (optional)
```

## Installation Steps

### 1. Install MetalLB

Install MetalLB components (controller and speakers):

```bash
kubectl apply -f metallb-install.yaml
```

Wait for all pods to be ready:

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=metallb -n metallb-system --timeout=300s
```

Verify installation:

```bash
kubectl get pods -n metallb-system
```

Expected output:
```
NAME                          READY   STATUS    RESTARTS   AGE
controller-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
speaker-xxxxx                 1/1     Running   0          1m
speaker-xxxxx                 1/1     Running   0          1m
speaker-xxxxx                 1/1     Running   0          1m
```

### 2. Configure IP Address Pool

The IP address pool defines which IPs MetalLB can assign to LoadBalancer services.

**File**: `ipaddresspool.yaml`

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.56.200-192.168.56.210  # Available IP range
```

Apply the configuration:

```bash
kubectl apply -f ipaddresspool.yaml
```

Verify:

```bash
kubectl get ipaddresspool -n metallb-system
```

### 3. Configure L2 Advertisement

The L2 advertisement tells MetalLB to advertise IPs using Layer 2 protocols (ARP/NDP).

**File**: `l2advertisement.yaml`

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
```

Apply the configuration:

```bash
kubectl apply -f l2advertisement.yaml
```

Verify:

```bash
kubectl get l2advertisement -n metallb-system
```

### 4. Deploy Test Application (Optional)

Deploy a test nginx application:

```bash
kubectl apply -f nginx-deployment.yaml
kubectl apply -f loadbalancer-service.yaml
```

## Verification

### Check MetalLB Status

```bash
# Check all MetalLB resources
kubectl get all -n metallb-system

# Check MetalLB configuration
kubectl get ipaddresspool,l2advertisement -n metallb-system
```

### Check LoadBalancer Service

```bash
kubectl get svc nginx-loadbalancer -n metallb-system
```

Expected output:
```
NAME                 TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)
nginx-loadbalancer   LoadBalancer   10.106.121.224   192.168.56.200   8080:30000/TCP
```

The `EXTERNAL-IP` should be assigned from your pool (not `<pending>`).

### Test Connectivity

From your host machine:

```bash
# Test the LoadBalancer IP
curl http://192.168.56.200:8080

# Check which node is the leader
kubectl get pods -n metallb-system -o wide
kubectl logs -n metallb-system -l component=speaker | grep "announce"
```

### Verify ARP

From your host machine:

```bash
# Check ARP table
arp -n | grep 192.168.56.200

# You should see the MAC address of one of your Kubernetes nodes
```

## Configuration Details

### IP Address Pool Settings

- **Range**: 192.168.56.200-192.168.56.210 (11 IPs)
- **Network**: Must be on the same subnet as Kubernetes nodes
- **Avoid conflicts**: Don't overlap with:
  - Node IPs (192.168.56.110-192.168.56.112)
  - DHCP ranges
  - Other statically assigned IPs

### L2 Advertisement Options

```yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
  
  # Optional: Limit to specific nodes
  nodeSelectors:
  - matchLabels:
      kubernetes.io/hostname: k8s-worker1
  
  # Optional: Limit to specific network interfaces
  interfaces:
  - eth1
```

## Troubleshooting

### LoadBalancer Stuck in "Pending" State

**Problem**: Service shows `<pending>` instead of an IP address.

**Solutions**:

1. Check MetalLB controller logs:
```bash
kubectl logs -n metallb-system deployment/controller
```

2. Verify IP pool exists:
```bash
kubectl get ipaddresspool -n metallb-system -o yaml
```

3. Verify L2 advertisement exists:
```bash
kubectl get l2advertisement -n metallb-system -o yaml
```

4. Check speaker logs:
```bash
kubectl logs -n metallb-system -l component=speaker
```

### IP Conflicts

**Problem**: Assigned IP conflicts with another device on the network.

**Solutions**:

1. Change the IP range in `ipaddresspool.yaml`:
```yaml
spec:
  addresses:
  - 192.168.56.220-192.168.56.230  # Different range
```

2. Check for conflicts on your network:
```bash
# From host machine
nmap -sn 192.168.56.0/24
```

### Service Unreachable

**Problem**: Can't access the LoadBalancer IP.

**Solutions**:

1. Verify pods are running:
```bash
kubectl get pods -l app=nginx
```

2. Check service endpoints:
```bash
kubectl get endpoints nginx-loadbalancer -n metallb-system
```

3. Check speaker logs for announcements:
```bash
kubectl logs -n metallb-system -l component=speaker | grep announce
```

4. Verify network connectivity from host to nodes:
```bash
ping 192.168.56.110
ping 192.168.56.111
ping 192.168.56.112
```

### Speaker Pods Not Running

**Problem**: MetalLB speaker pods are not running.

**Solutions**:

1. Check pod status:
```bash
kubectl describe pod -n metallb-system -l component=speaker
```

2. Check node taints:
```bash
kubectl get nodes -o json | jq '.items[].spec.taints'
```

3. MetalLB speakers need to run on all nodes. Check if nodes have the taint:
```
node.kubernetes.io/exclude-from-external-load-balancers
```

If they do, remove it:
```bash
kubectl taint nodes --all node.kubernetes.io/exclude-from-external-load-balancers-
```

## Switching to BGP Mode

If you need to switch from L2 to BGP mode:

1. Delete the L2 advertisement:
```bash
kubectl delete -f l2advertisement.yaml
```

2. Apply BGP configuration (see [README-BGP.md](README-BGP.md)):
```bash
kubectl apply -f BGPPeer.yml
kubectl apply -f BGPAdvertisement.yml
```

The `ipaddresspool.yaml` can remain the same for both modes.

## Uninstallation

To remove L2 configuration:

```bash
# Remove test application (if deployed)
kubectl delete -f loadbalancer-service.yaml
kubectl delete -f nginx-clusterip.yaml
kubectl delete -f nginx-deployment.yaml

# Remove L2 configuration
kubectl delete -f ARP/l2advertisement.yaml
kubectl delete -f ipaddresspool.yaml

# Remove MetalLB (optional)
kubectl delete -f metallb-install.yaml
```

## Best Practices

1. **IP Planning**: Reserve a dedicated range for MetalLB that won't conflict with other services
2. **Documentation**: Document which IP ranges are used for what purposes
3. **Monitoring**: Monitor MetalLB logs for issues
4. **Testing**: Test failover by cordoning nodes to ensure high availability works
5. **Backup**: Keep configuration files in version control

## Additional Resources

- [MetalLB Official Documentation](https://metallb.universe.tf/)
- [Layer 2 Configuration Guide](https://metallb.universe.tf/configuration/_advanced_l2_configuration/)
- [MetalLB Concepts](https://metallb.universe.tf/concepts/)

## Network Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    Host Machine                         │
│                  (192.168.56.1)                         │
│                                                         │
│  curl http://192.168.56.200:8080                        │
└────────────────────┬────────────────────────────────────┘
                     │ ARP: Who has 192.168.56.200?
                     │
    ┌────────────────┴────────────────┐
    │         192.168.56.0/24         │
    │         (vboxnet0)              │
    └────┬──────────┬─────────┬───────┘
         │          │         │
    ┌────▼────┐┌───▼─────┐┌──▼──────┐
    │ Master  ││ Worker1 ││ Worker2 │
    │  .110   ││  .111   ││  .112   │
    └─────────┘└───┬─────┘└─────────┘
                   │
              Leader responds
            (ARP: .200 is at MAC)
                   │
            ┌──────▼──────┐
            │   Service   │
            │ (ClusterIP) │
            └──────┬──────┘
                   │
        ┌──────────┴──────────┐
        │                     │
    ┌───▼────┐           ┌───▼────┐
    │ nginx  │           │ nginx  │
    │  pod   │           │  pod   │
    └────────┘           └────────┘
```

