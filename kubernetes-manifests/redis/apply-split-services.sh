#!/bin/bash

# Script to apply Redis master/replica service splitting
# This enables proper read/write splitting at the HAProxy level

set -e

echo "=================================================="
echo "Redis Master/Replica Service Splitting Setup"
echo "=================================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if redis namespace exists
if ! kubectl get namespace redis &> /dev/null; then
    echo "❌ Error: redis namespace does not exist"
    echo "Please create it first: kubectl create namespace redis"
    exit 1
fi

# Check current Redis pods
echo "📊 Current Redis pods:"
kubectl get pods -n redis -o wide
echo ""

# Check which pod is master
echo "🔍 Checking Redis roles..."
REDIS_0_ROLE=$(kubectl exec -n redis redis-0 -- redis-cli INFO replication 2>/dev/null | grep "role:" | cut -d: -f2 | tr -d '\r')
REDIS_1_ROLE=$(kubectl exec -n redis redis-1 -- redis-cli INFO replication 2>/dev/null | grep "role:" | cut -d: -f2 | tr -d '\r')

echo "  redis-0: $REDIS_0_ROLE"
echo "  redis-1: $REDIS_1_ROLE"
echo ""

if [ "$REDIS_0_ROLE" != "master" ]; then
    echo "⚠️  WARNING: redis-0 is not the master!"
    echo "   This configuration assumes redis-0 is always the master."
    echo "   You may need to adjust the services or trigger a failover."
    echo ""
fi

# Check if old service exists
if kubectl get service redis-nodeport -n redis &> /dev/null; then
    echo "🗑️  Deleting old redis-nodeport service..."
    kubectl delete service redis-nodeport -n redis
    echo "✅ Old service deleted"
    echo ""
fi

# Apply new services
echo "🚀 Applying new master/replica services..."
kubectl apply -f "$(dirname "$0")/redis-services-split.yml"
echo ""

# Wait a moment for services to be ready
sleep 2

# Show new services
echo "📋 New Redis services:"
kubectl get services -n redis
echo ""

# Get node IPs
echo "🌐 Node information:"
kubectl get nodes -o wide | grep -E "NAME|worker"
echo ""

# Get service endpoints
echo "🎯 Service endpoints:"
echo ""
echo "Master service (redis-master):"
kubectl get endpoints redis-master -n redis
echo ""
echo "Replica service (redis-replica):"
kubectl get endpoints redis-replica -n redis
echo ""

# Show NodePort details
echo "📡 NodePort details:"
MASTER_NODEPORT=$(kubectl get service redis-master -n redis -o jsonpath='{.spec.ports[0].nodePort}')
REPLICA_NODEPORT=$(kubectl get service redis-replica -n redis -o jsonpath='{.spec.ports[0].nodePort}')

echo "  Master NodePort:  $MASTER_NODEPORT (writes)"
echo "  Replica NodePort: $REPLICA_NODEPORT (reads)"
echo ""

# Determine which node each pod is on
REDIS_0_NODE=$(kubectl get pod redis-0 -n redis -o jsonpath='{.spec.nodeName}')
REDIS_1_NODE=$(kubectl get pod redis-1 -n redis -o jsonpath='{.spec.nodeName}')

echo "📍 Pod locations:"
echo "  redis-0 (master):  $REDIS_0_NODE"
echo "  redis-1 (replica): $REDIS_1_NODE"
echo ""

# Get node IPs
WORKER1_IP=$(kubectl get node k8s-worker1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
WORKER2_IP=$(kubectl get node k8s-worker2 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')

echo "🔧 HAProxy configuration should use:"
echo ""
echo "  # Master backend (writes)"
echo "  server redis-master $WORKER1_IP:$MASTER_NODEPORT check inter 5s fall 3 rise 2"
echo ""
echo "  # Replica backend (reads)"
echo "  server redis-replica $WORKER2_IP:$REPLICA_NODEPORT check inter 5s fall 3 rise 2"
echo ""

echo "=================================================="
echo "✅ Setup complete!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "1. Update HAProxy configuration with the IPs shown above"
echo "2. Restart HAProxy: cd ha_proxy && docker-compose restart"
echo "3. Test writes: redis-cli -h localhost -p 6379 SET key value"
echo "4. Test reads:  redis-cli -h localhost -p 6380 GET key"
echo ""

