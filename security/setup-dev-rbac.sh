#!/bin/bash

# Script to set up RBAC for dev user with access only to metallb namespace

echo "======================================"
echo "Setting up RBAC for dev user"
echo "======================================"

# Check if metallb-system namespace exists
echo ""
echo "Checking for metallb-system namespace..."
if kubectl get namespace metallb-system &> /dev/null; then
    echo "✓ metallb-system namespace found"
    NAMESPACE="metallb-system"
elif kubectl get namespace metallb &> /dev/null; then
    echo "✓ metallb namespace found"
    NAMESPACE="metallb"
else
    echo "⚠ Warning: Neither metallb-system nor metallb namespace found"
    echo "Creating metallb namespace..."
    kubectl create namespace metallb
    NAMESPACE="metallb"
fi

echo ""
echo "Applying ClusterRole and RoleBinding..."
kubectl apply -f dev-clusterrole.yml

echo ""
echo "======================================"
echo "RBAC Setup Complete!"
echo "======================================"
echo ""
echo "Verifying RBAC configuration:"
echo ""
echo "1. ClusterRole:"
kubectl get clusterrole dev-namespace-admin

echo ""
echo "2. RoleBinding in $NAMESPACE:"
kubectl get rolebinding dev-metallb-binding -n $NAMESPACE

echo ""
echo "======================================"
echo "Testing dev user permissions"
echo "======================================"
echo ""
echo "To test the dev user access, use:"
echo ""
echo "  kubectl auth can-i get pods --as=dev -n $NAMESPACE"
echo "  kubectl auth can-i get pods --as=dev -n default"
echo ""
echo "The first command should return 'yes' (allowed)"
echo "The second command should return 'no' (denied)"
echo ""
echo "======================================"
echo "Using dev credentials"
echo "======================================"
echo ""
echo "To use the dev user credentials, run:"
echo ""
echo "  kubectl --client-certificate=dev.crt \\"
echo "    --client-key=dev.key \\"
echo "    --certificate-authority=/etc/kubernetes/pki/ca.crt \\"
echo "    get pods -n $NAMESPACE"
echo ""

