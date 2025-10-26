#!/bin/bash
# Complete Kubernetes cluster setup from scratch (CONTAINERD VERSION)

set -e  # Exit on error

echo "=========================================="
echo "  Kubernetes Cluster Clean Installation"
echo "  Container Runtime: containerd"
echo "=========================================="
echo ""

# Step 1: Reset
echo ">>> Step 1/5: Resetting cluster..."
sudo kubeadm reset -f --cri-socket unix:///run/containerd/containerd.sock
sudo rm -rf /etc/kubernetes/ /var/lib/etcd/ /var/lib/kubelet/* /etc/cni/net.d/* $HOME/.kube/
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X

echo ""
echo ">>> Restarting containerd and kubelet..."
sudo systemctl restart containerd
sudo systemctl restart kubelet
sleep 5

# Step 2: Kernel params
echo ""
echo ">>> Step 2/5: Setting kernel parameters..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system > /dev/null

echo ""
echo ">>> Verifying kernel parameters..."
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables net.ipv4.ip_forward | grep "= 1"

# Step 3: Verify containerd config
echo ""
echo ">>> Step 3/5: Verifying containerd configuration..."
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# Enable SystemdCgroup
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl restart containerd
sleep 3

echo "✅ Containerd configured with SystemdCgroup"

# Step 4: Get IP
echo ""
echo ">>> Step 4/5: Detecting master IP..."
MASTER_IP=$(ip addr show | grep "inet 192.168" | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | head -1)

if [ -z "$MASTER_IP" ]; then
    echo "⚠️  Could not auto-detect 192.168.x.x IP"
    echo "Available IPs:"
    ip addr show | grep "inet " | grep -v "127.0.0.1"
    echo ""
    read -p "Enter your master node IP address: " MASTER_IP
fi

echo "✅ Using Master IP: $MASTER_IP"

# Step 5: Initialize
echo ""
echo ">>> Step 5/5: Initializing control plane..."
echo "This takes 3-5 minutes. Please wait..."
echo ""

sudo kubeadm init \
  --apiserver-advertise-address=$MASTER_IP \
  --pod-network-cidr=10.244.0.0/16 \
  --control-plane-endpoint=$MASTER_IP:6443 \
  --cri-socket unix:///run/containerd/containerd.sock \
  --v=5

# Step 6: Configure kubectl
echo ""
echo ">>> Configuring kubectl..."
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Step 7: Install Flannel
echo ""
echo ">>> Installing Flannel CNI..."
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Step 8: Remove taint for single-node cluster
echo ""
echo ">>> Removing master taint (for single-node setup)..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true

echo ""
echo "=========================================="
echo "  ✅ Installation Complete!"
echo "=========================================="
echo ""
echo "Waiting 90 seconds for all pods to start..."
sleep 90

echo ""
echo "=== Cluster Status ==="
kubectl get nodes
echo ""
kubectl get pods -A
echo ""
echo "=== Container Status ==="
sudo crictl ps
