# Accessing ArgoCD API Server in Vagrant Kubernetes Cluster

## Current Setup
- **Master Node IP**: 192.168.56.110
- **Worker1 IP**: 192.168.56.111
- **Worker2 IP**: 192.168.56.112
- **ArgoCD Server Service**: ClusterIP (10.97.106.43)

## Access Methods

### Method 1: NodePort Service (Recommended for Vagrant)

Change the `argocd-server` service to NodePort to access it via the node's IP address.

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
```

Then get the NodePort:
```bash
kubectl get svc argocd-server -n argocd
```

Access ArgoCD at: `http://192.168.56.110:<nodeport>` or `https://192.168.56.110:<nodeport>`

### Method 2: Port Forwarding (Quick Testing)

Forward the ArgoCD server port to your local machine:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0
```

Then access ArgoCD at: `https://localhost:8080`

**Note**: This needs to run continuously and will stop when you close the terminal.

### Method 3: LoadBalancer with MetalLB (If MetalLB is installed)

If you have MetalLB installed, change the service type to LoadBalancer:

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'
```

### Method 4: Ingress (If Ingress Controller is installed)

Create an Ingress resource to expose ArgoCD. See `argocd-ingress.yaml` in this directory.

### Method 5: Traefik + Gateway API (with MetalLB BGP)

Expose ArgoCD via **Traefik** as the Gateway API implementation; MetalLB (BGP) assigns an external IP to the Traefik LoadBalancer.

1. Install Gateway API CRDs, Traefik with Gateway API provider, then create the Gateway and HTTPRoute. Full steps and manifests are in **`traefik-gateway/`**; see `traefik-gateway/README.md`.
2. After installation, get the Gateway IP (MetalLB-assigned):
   ```bash
   kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
   ```
3. Access ArgoCD at `http://<GATEWAY_IP>` (e.g. `http://192.168.56.200`).

CLI login:
```bash
argocd login <GATEWAY_IP> --username admin --password <password> --insecure
```

## Getting the Initial Admin Password

The initial admin password is stored in a Kubernetes secret:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

**Username**: `admin`

## ArgoCD CLI Access

Install the ArgoCD CLI:
```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

Login via CLI (after exposing the service):
```bash
# For NodePort
argocd login 192.168.56.110:<nodeport> --username admin --password <password> --insecure

# For port-forward
argocd login localhost:8080 --username admin --password <password> --insecure
```

## API Access

Once logged in, you can access the ArgoCD API:

### Using the Web UI
- Navigate to the ArgoCD URL in your browser
- Login with admin credentials
- Go to User Info → Generate API Token

### Using CLI to get API token
```bash
argocd account generate-token --account admin
```

### Making API Calls
```bash
# Get API token
TOKEN=$(argocd account generate-token --account admin)

# Example API call - list applications
curl -k -H "Authorization: Bearer $TOKEN" https://192.168.56.110:<nodeport>/api/v1/applications

# Example - get application details
curl -k -H "Authorization: Bearer $TOKEN" https://192.168.56.110:<nodeport>/api/v1/applications/<app-name>
```

## Troubleshooting

### Check ArgoCD Server Logs
```bash
kubectl logs -n argocd deployment/argocd-server -f
```

### Check All ArgoCD Pods
```bash
kubectl get pods -n argocd
```

### Verify Service Endpoints
```bash
kubectl get endpoints -n argocd argocd-server
```

### Test Internal Connectivity
```bash
kubectl run test-pod --rm -it --image=curlimages/curl --restart=Never -- sh
# Inside the pod:
curl -k https://argocd-server.argocd.svc.cluster.local
```

## Security Considerations

1. **Disable TLS (for testing only)**:
   ```bash
   kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'
   kubectl rollout restart deployment argocd-server -n argocd
   ```

2. **Change Admin Password**:
   ```bash
   argocd account update-password
   ```

3. **For production**: Use proper TLS certificates and Gateway API / Ingress with cert-manager.

