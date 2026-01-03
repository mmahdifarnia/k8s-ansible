#!/bin/bash

# Quick Access Script for ArgoCD in Vagrant Kubernetes Cluster

set -e

echo "==================================="
echo "ArgoCD Quick Access Setup"
echo "==================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if ArgoCD is running
echo "Checking ArgoCD status..."
if ! kubectl get namespace argocd &> /dev/null; then
    echo "Error: ArgoCD namespace not found. Please install ArgoCD first."
    exit 1
fi

echo -e "${GREEN}✓${NC} ArgoCD namespace found"

# Check if pods are running
PODS_READY=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -c "Running" || echo "0")
echo -e "${GREEN}✓${NC} ArgoCD pods running: $PODS_READY"

echo ""
echo "Choose an access method:"
echo "1) NodePort (Recommended for Vagrant)"
echo "2) Port Forward (Quick testing)"
echo "3) Get Admin Password"
echo "4) Install ArgoCD CLI"
echo "5) Show current service status"
echo "6) Disable TLS (insecure mode for testing)"
echo ""
read -p "Enter your choice [1-6]: " choice

case $choice in
    1)
        echo ""
        echo "Setting up NodePort access..."
        kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "NodePort"}}'
        
        # Wait a moment for the patch to apply
        sleep 2
        
        HTTP_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
        HTTPS_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
        
        echo ""
        echo -e "${GREEN}✓${NC} NodePort configured successfully!"
        echo ""
        echo "Access ArgoCD at:"
        echo -e "  HTTP:  ${YELLOW}http://192.168.56.110:${HTTP_PORT}${NC}"
        echo -e "  HTTPS: ${YELLOW}https://192.168.56.110:${HTTPS_PORT}${NC}"
        echo ""
        echo "You can also use worker node IPs:"
        echo "  - http://192.168.56.111:${HTTP_PORT}"
        echo "  - http://192.168.56.112:${HTTP_PORT}"
        ;;
    
    2)
        echo ""
        echo "Starting port forwarding..."
        echo -e "${YELLOW}Note: This will run in the foreground. Press Ctrl+C to stop.${NC}"
        echo ""
        echo "Access ArgoCD at: https://localhost:8080"
        echo ""
        kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0
        ;;
    
    3)
        echo ""
        echo "Retrieving admin password..."
        PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d)
        
        if [ -z "$PASSWORD" ]; then
            echo "Error: Could not retrieve password. The secret might not exist."
            exit 1
        fi
        
        echo ""
        echo -e "${GREEN}ArgoCD Admin Credentials:${NC}"
        echo -e "  Username: ${YELLOW}admin${NC}"
        echo -e "  Password: ${YELLOW}${PASSWORD}${NC}"
        echo ""
        ;;
    
    4)
        echo ""
        echo "Installing ArgoCD CLI..."
        
        # Check if already installed
        if command -v argocd &> /dev/null; then
            CURRENT_VERSION=$(argocd version --client --short 2>/dev/null || echo "unknown")
            echo "ArgoCD CLI is already installed: $CURRENT_VERSION"
            read -p "Do you want to reinstall? [y/N]: " reinstall
            if [[ ! $reinstall =~ ^[Yy]$ ]]; then
                exit 0
            fi
        fi
        
        echo "Downloading latest ArgoCD CLI..."
        curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
        
        echo "Installing ArgoCD CLI to /usr/local/bin/argocd..."
        sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
        rm argocd-linux-amd64
        
        echo -e "${GREEN}✓${NC} ArgoCD CLI installed successfully!"
        argocd version --client
        ;;
    
    5)
        echo ""
        echo "Current ArgoCD Service Status:"
        echo ""
        kubectl get svc argocd-server -n argocd
        echo ""
        echo "All ArgoCD Services:"
        kubectl get svc -n argocd
        echo ""
        echo "ArgoCD Pods:"
        kubectl get pods -n argocd
        ;;
    
    6)
        echo ""
        echo -e "${YELLOW}Warning: This will disable TLS verification (insecure mode)${NC}"
        echo "This is only recommended for testing purposes."
        read -p "Are you sure? [y/N]: " confirm
        
        if [[ $confirm =~ ^[Yy]$ ]]; then
            echo "Disabling TLS..."
            kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'
            echo "Restarting argocd-server..."
            kubectl rollout restart deployment argocd-server -n argocd
            echo -e "${GREEN}✓${NC} TLS disabled. Waiting for pods to restart..."
            kubectl rollout status deployment argocd-server -n argocd
            echo -e "${GREEN}✓${NC} Done! You can now access ArgoCD via HTTP."
        else
            echo "Cancelled."
        fi
        ;;
    
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
echo "==================================="
echo "Setup complete!"
echo "==================================="

