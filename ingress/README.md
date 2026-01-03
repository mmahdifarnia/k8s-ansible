# Kubernetes Ingress Setup with MetalLB

This directory contains a complete Kubernetes ingress setup with MetalLB load balancing, featuring three nginx applications accessible via path-based routing.

## 📋 Overview

This setup demonstrates:
- **MetalLB integration** for bare-metal load balancing
- **NGINX Ingress Controller** for HTTP/HTTPS traffic routing
- **Path-based routing** to multiple applications
- **Resource-constrained deployments** with proper limits
- **Custom nginx configurations** via ConfigMaps

## 🏗️ Architecture

```
Browser → MetalLB (192.168.56.201:80) → NGINX Ingress → Services → Pods
```

### Components Flow:
1. **MetalLB LoadBalancer**: External IP `192.168.56.201`
2. **NGINX Ingress Controller**: Path-based routing
3. **ClusterIP Services**: Internal load balancing
4. **Deployments**: Application pods with resource limits

## 📁 Files Structure

| File | Purpose |
|------|---------|
| `nginx-apps-ingress.yaml` | Main ingress rules for path-based routing |
| `nginx-app1-deployment.yaml` | Blue-themed nginx deployment |
| `nginx-app1-service.yaml` | Service for app1 |
| `nginx-app1-configmap.yaml` | Nginx config and HTML for app1 |
| `nginx-app2-deployment.yaml` | Green-themed nginx deployment |
| `nginx-app2-service.yaml` | Service for app2 |
| `nginx-app2-configmap.yaml` | Nginx config and HTML for app2 |
| `nginx-app3-deployment.yaml` | Purple-themed nginx deployment |
| `nginx-app3-service.yaml` | Service for app3 |
| `nginx-app3-configmap.yaml` | Nginx config and HTML for app3 |

## 🚀 Deployment

### Prerequisites
- Kubernetes cluster with MetalLB installed
- NGINX Ingress Controller deployed
- kubectl configured to access your cluster

### Deploy All Components
```bash
cd /path/to/ingress
kubectl apply -f .
```

### Verify Deployment
```bash
# Check pods
kubectl get pods -l 'app in (nginx-app1,nginx-app2,nginx-app3)'

# Check services
kubectl get svc -l 'app in (nginx-app1,nginx-app2,nginx-app3)'

# Check ingress
kubectl get ingress
```

## 🌐 Access Applications

After deployment, applications are accessible via:

| Application | URL | Theme | Description |
|-------------|-----|-------|-------------|
| **App 1** | `http://192.168.56.201/app1` | Blue | Primary application (default) |
| **App 2** | `http://192.168.56.201/app2` | Green | Secondary application |
| **App 3** | `http://192.168.56.201/app3` | Purple | Tertiary application |
| **Default** | `http://192.168.56.201/` | Blue | Root path → App 1 |

### Expected Response
Each application displays:
- Distinct color theme
- Application title
- Pod hostname (shows load balancing)
- Current timestamp

## ⚙️ Configuration Details

### Resource Limits
All deployments include resource constraints:
```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "100m"
  limits:
    memory: "128Mi"
    cpu: "200m"
```

### Ingress Configuration
- **Class**: `nginx`
- **Rewrite Target**: `/`
- **Path Type**: `Prefix`
- **Load Balancing**: Round-robin across 2 replicas each

### MetalLB Integration
- **IP Pool**: `192.168.56.200-192.168.56.210`
- **Mode**: Layer 2 (ARP-based)
- **External IP**: `192.168.56.201` (assigned automatically)

## 🔍 Testing

### Health Checks
```bash
# Test all applications
curl http://192.168.56.201/app1
curl http://192.168.56.201/app2
curl http://192.168.56.201/app3
curl http://192.168.56.201/  # Default route
```

### Load Balancing Verification
```bash
# Should show different pod hostnames
for i in {1..6}; do
  curl -s http://192.168.56.201/app1 | grep "Pod:"
done
```

### DNS Resolution
```bash
# Verify external access
nslookup 192.168.56.201
curl -I http://192.168.56.201/app1
```

## 🛠️ Troubleshooting

### Common Issues

**Ingress not accessible:**
```bash
# Check MetalLB status
kubectl get svc -n ingress-nginx

# Check ingress controller logs
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller
```

**Pods not starting:**
```bash
# Check pod status and events
kubectl describe pod <pod-name>
kubectl get events --sort-by=.metadata.creationTimestamp
```

**Resource limits exceeded:**
```bash
# Check resource usage
kubectl top pods
kubectl describe node <node-name>
```

### Debug Commands
```bash
# View ingress details
kubectl describe ingress nginx-apps-ingress

# Check service endpoints
kubectl get endpoints

# Test internal connectivity
kubectl run test --rm -it --image=busybox -- wget -O- http://nginx-app1-service:80
```

## 🧹 Cleanup

Remove all components:
```bash
kubectl delete -f .
```

Remove specific applications:
```bash
kubectl delete deployment,service,configmap -l app=nginx-app1
kubectl delete deployment,service,configmap -l app=nginx-app2
kubectl delete deployment,service,configmap -l app=nginx-app3
kubectl delete ingress nginx-apps-ingress default-ingress
```

## 📊 Monitoring

Monitor your applications:
```bash
# Resource usage
kubectl top pods

# Network traffic
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller -f

# Service health
kubectl get endpoints -o wide
```

## 🔒 Security Considerations

- All services use HTTP (port 80)
- No TLS/SSL configuration included
- Resource limits prevent resource exhaustion
- Network policies not implemented (consider adding)

## 📈 Scaling

Scale individual applications:
```bash
kubectl scale deployment nginx-app1 --replicas=3
kubectl scale deployment nginx-app2 --replicas=5
```

## 🤝 Contributing

To modify this setup:
1. Update the YAML files as needed
2. Test changes locally
3. Update this README with any new features
4. Ensure resource limits are appropriate

---

**Note**: This setup assumes MetalLB is configured with IP pool `192.168.56.200-192.168.56.210` and NGINX Ingress Controller is installed in the `ingress-nginx` namespace.
