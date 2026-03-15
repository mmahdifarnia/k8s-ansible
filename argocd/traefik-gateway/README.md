# ArgoCD Access via Traefik and Gateway API

This directory contains manifests to expose ArgoCD using **Traefik** as the Gateway API implementation, with **MetalLB (BGP)** providing the external IP for the gateway.

## Prerequisites

- Kubernetes cluster (Vagrant VMs)
- MetalLB installed with BGP (see `metallb/BGP/`)
- ArgoCD installed in namespace `argocd`
- `kubectl` and Helm 3

## Architecture

```
                    MetalLB (BGP)
                         │
                         ▼
              ┌──────────────────────┐
              │  Traefik LoadBalancer │  ← IP from pool (e.g. 192.168.56.200)
              │  (Gateway API)        │
              └──────────┬───────────┘
                         │
                         │ HTTPRoute: /argocd → argocd-server
                         ▼
              ┌──────────────────────┐
              │  argocd-server       │  (ClusterIP, port 80/443)
              │  namespace: argocd   │
              └──────────────────────┘
```

## Installation Order

### 1. Install Gateway API CRDs

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/standard-install.yaml
```

### 2. Create namespace and RBAC for Traefik

```bash
kubectl create namespace traefik
kubectl apply -f kubernetes-gateway-rbac.yaml
```

### 3. Install Traefik with Gateway API provider

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik \
  -n traefik \
  -f traefik-helm-values.yaml
```

Wait until the Traefik LoadBalancer service gets an external IP from MetalLB:

```bash
kubectl get svc -n traefik -w
```

### 4. Create GatewayClass, Gateway, and route to ArgoCD

```bash
# GatewayClass (if not created by Traefik chart)
kubectl apply -f gatewayclass.yaml

# Gateway (listener 80) and HTTPRoute for ArgoCD at /argocd
kubectl apply -f gateway.yaml
kubectl apply -f argocd-httproute.yaml
kubectl apply -f argocd-reference-grant.yaml

# Configure ArgoCD to serve under /argocd (required for path-based routing)
kubectl apply -f argocd-rootpath-patch.yaml
kubectl rollout restart deployment argocd-server -n argocd

# Optional: if Gateway API gives 404, use Ingress instead (Traefik Ingress provider)
kubectl apply -f argocd-ingress.yaml
```

### 5. Verify

```bash
# Gateway should be Programmed and have an address
kubectl get gateway -n traefik

# HTTPRoute should be accepted
kubectl get httproute -n traefik

# Get the Gateway IP (same as Traefik LoadBalancer)
kubectl get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Access ArgoCD at `http://<GATEWAY_IP>/argocd` (e.g. `http://192.168.56.200/argocd`). Use HTTPS if you configure TLS on the Gateway later.

## Files

| File | Description |
|------|-------------|
| `traefik-helm-values.yaml` | Helm values: Gateway API provider, LoadBalancer service |
| `kubernetes-gateway-rbac.yaml` | RBAC for Traefik Gateway API (namespace `traefik`) |
| `gatewayclass.yaml` | GatewayClass for Traefik (apply if chart doesn't create it) |
| `gateway.yaml` | Gateway API Gateway (listener 80; HTTPS optional) |
| `argocd-httproute.yaml` | HTTPRoute forwarding `/` to argocd-server |
| `argocd-reference-grant.yaml` | ReferenceGrant so HTTPRoute can reference argocd-server |
| `argocd-rootpath-patch.yaml` | ConfigMap patch so ArgoCD serves under /argocd |
| `argocd-ingress.yaml` | Ingress /argocd → argocd-server (use if Gateway API returns 404) |

## Optional: TLS

To serve ArgoCD over HTTPS, create a TLS secret in `traefik` and add a TLS listener to the Gateway, or use a TLS termination at Traefik with a certificate.

## Troubleshooting

- **No external IP on Traefik**: Ensure MetalLB and BGP are running; check `kubectl get svc -n metallb-system` and BGP peer status.
- **502 Bad Gateway**: Ensure ArgoCD server pods are running: `kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server`.
- **Gateway not Programmed**: Check Traefik logs: `kubectl logs -n traefik -l app.kubernetes.io/name=traefik`.
- **404 with Gateway API**: Apply `argocd-ingress.yaml` and upgrade Traefik with Ingress provider enabled (`traefik-helm-values.yaml`). Traefik will route via Ingress instead.
