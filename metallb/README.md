# MetalLB Setup for Vagrant Kubernetes Cluster

This directory contains all the necessary files to install and configure MetalLB on your Vagrant Kubernetes cluster.

## 📖 Documentation

This directory provides **two modes** for MetalLB configuration:

- **[Layer 2 Mode (README-L2.md)](ARP/README-L2.md)** - Simple ARP-based load balancing (recommended for getting started)
- **[BGP Mode (README-BGP.md)](BGP/README-BGP.md)** - Advanced routing with BGP protocol (recommended for production)

## Configuration Details

### IP Address Pool
- **Range**: 192.168.56.200-192.168.56.210
- **Protocol**: Layer 2 (ARP)
- **Namespace**: metallb-system

### Services
- **nginx-loadbalancer**: External LoadBalancer service (port 8080 → 80)

### Deployment
- **nginx-deployment**: 2 replicas of nginx:latest
- **Labels**: app=nginx

### IP conflicts

If you get IP conflicts, modify the IP range in `ipaddresspool.yaml` to use different addresses that don't conflict with your Vagrant node IPs (192.168.56.110-192.168.56.112).

## Choosing Between L2 and BGP Mode

### Use Layer 2 Mode When:
- You're getting started with MetalLB
- All nodes are on the same network segment
- You don't have access to BGP routers
- Simplicity is more important than advanced features
- Traffic through a single node is acceptable

### Use BGP Mode When:
- You need true load balancing across multiple nodes
- You have BGP-capable routers
- Services need to be accessible across subnets
- Fast failover is critical (< 1 second)
- You're deploying to production

## Uninstallation
To remove MetalLB completely:

```bash
kubectl delete -f loadbalancer-service.yaml
kubectl delete -f nginx-deployment.yaml
kubectl delete -f l2advertisement.yaml
kubectl delete -f ipaddresspool.yaml
kubectl delete -f metallb-install.yaml
```
