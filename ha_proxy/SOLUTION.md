# Redis Read/Write Splitting - The Real Problem & Solutions

## The Problem You Discovered 🎯

You're absolutely correct! The issue is that the **Kubernetes NodePort Service** (`redis-nodeport`) is load balancing between **ALL Redis pods** (both master and replicas).

### Current Architecture (Problematic)

```
Your Laptop
    ↓
HAProxy Port 6379 (writes)
    ↓
192.168.56.111:30917 (NodePort Service)
    ↓
Kubernetes Service Load Balances Between:
    ├─→ redis-0 (10.244.1.60) - MASTER ✅ writes work
    └─→ redis-1 (10.244.2.47) - REPLICA ❌ writes fail (READONLY error)
```

This is why you see:

- **First attempt**: Routes to replica → `(error) READONLY You can't write against a read only replica.`
- **Second attempt**: Routes to master → `OK`

## Solutions

You have **three options** to fix this:

---

## Option 1: Create Separate Services for Master and Replica (RECOMMENDED)

This is the **cleanest Kubernetes-native solution**.

### Create Two Services:

1. **Master-only service** with NodePort 30917
2. **Replica-only service** with NodePort 30918

### Implementation:

Create a new file: `kubernetes-manifests/redis/redis-services.yml`

```yaml
---
# Headless service (keep as is)
apiVersion: v1
kind: Service
metadata:
  name: redis-headless
  namespace: redis
spec:
  clusterIP: None
  selector:
    app: redis
  ports:
    - port: 6379
      targetPort: 6379
---
# Master-only service (for writes)
apiVersion: v1
kind: Service
metadata:
  name: redis-master
  namespace: redis
  labels:
    app: redis
    role: master
spec:
  type: NodePort
  selector:
    app: redis
    statefulset.kubernetes.io/pod-name: redis-0 # Target only redis-0 (master)
  ports:
    - name: redis-master
      port: 6379
      targetPort: 6379
      protocol: TCP
      nodePort: 30917
  externalTrafficPolicy: Local # Important: route to local pod only
---
# Replica-only service (for reads)
apiVersion: v1
kind: Service
metadata:
  name: redis-replica
  namespace: redis
  labels:
    app: redis
    role: replica
spec:
  type: NodePort
  selector:
    app: redis
    statefulset.kubernetes.io/pod-name: redis-1 # Target only redis-1 (replica)
  ports:
    - name: redis-replica
      port: 6379
      targetPort: 6379
      protocol: TCP
      nodePort: 30918
  externalTrafficPolicy: Local # Important: route to local pod only
```

### Apply the Changes:

```bash
# Delete old service
kubectl delete service redis-nodeport -n redis

# Apply new services
kubectl apply -f kubernetes-manifests/redis/redis-services.yml

# Verify
kubectl get svc -n redis
```

### Update HAProxy Configuration:

```cfg
# Backend for write operations (Master only)
backend redis_write_backend
    mode tcp

    timeout connect 3s
    timeout server 30s

    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG

    # Master on worker1 (where redis-0 runs)
    server redis-master 192.168.56.111:30917 check inter 5s fall 3 rise 2

# Backend for read operations (Replica only)
backend redis_read_backend
    mode tcp
    balance leastconn

    timeout connect 3s
    timeout server 30s

    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG

    # Replica on worker2 (where redis-1 runs)
    server redis-replica 192.168.56.112:30918 check inter 5s fall 3 rise 2
```

**Pros:**

- ✅ Kubernetes-native solution
- ✅ Works with node failures (if using multiple replicas)
- ✅ Easy to scale replicas
- ✅ Clean separation of concerns

**Cons:**

- ⚠️ Requires `externalTrafficPolicy: Local` which means traffic only goes to local node
- ⚠️ If redis-0 is on worker2, you need to access worker2's IP

---

## Option 2: Use Pod IPs Directly (SIMPLE BUT FRAGILE)

Connect HAProxy directly to the pod IPs, bypassing Kubernetes services.

### Current Pod IPs:

- **redis-0** (master): `10.244.1.60` on k8s-worker1
- **redis-1** (replica): `10.244.2.47` on k8s-worker2

### Update HAProxy Configuration:

```cfg
# Backend for write operations (Master only)
backend redis_write_backend
    mode tcp

    timeout connect 3s
    timeout server 30s

    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG

    # Direct to master pod IP
    server redis-master 10.244.1.60:6379 check inter 5s fall 3 rise 2

# Backend for read operations (Replica only)
backend redis_read_backend
    mode tcp
    balance leastconn

    timeout connect 3s
    timeout server 30s

    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG

    # Direct to replica pod IP
    server redis-replica 10.244.2.47:6379 check inter 5s fall 3 rise 2
```

**Important:** HAProxy needs network access to pod IPs. This works if:

- HAProxy is running on one of the Kubernetes nodes
- HAProxy is in a pod with proper network access
- Your Docker network can reach the pod network (may need routing)

**Pros:**

- ✅ Simple and direct
- ✅ No Kubernetes service changes needed
- ✅ Guaranteed to route to correct pod

**Cons:**

- ❌ Pod IPs change when pods restart
- ❌ Requires manual updates
- ❌ HAProxy must be able to reach pod network
- ❌ Not production-ready

---

## Option 3: Use Headless Service with Specific Pod DNS (BEST FOR STATEFULSET)

StatefulSets provide predictable DNS names for each pod.

### Pod DNS Names:

- **Master**: `redis-0.redis-headless.redis.svc.cluster.local`
- **Replica**: `redis-1.redis-headless.redis.svc.cluster.local`

### Update HAProxy Configuration:

```cfg
# Backend for write operations (Master only)
backend redis_write_backend
    mode tcp

    timeout connect 3s
    timeout server 30s

    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG

    # Direct to master pod via DNS
    server redis-master redis-0.redis-headless.redis.svc.cluster.local:6379 check inter 5s fall 3 rise 2

# Backend for read operations (Replica only)
backend redis_read_backend
    mode tcp
    balance leastconn

    timeout connect 3s
    timeout server 30s

    option tcp-check
    tcp-check connect
    tcp-check send PING\r\n
    tcp-check expect string +PONG

    # Direct to replica pod via DNS
    server redis-replica redis-1.redis-headless.redis.svc.cluster.local:6379 check inter 5s fall 3 rise 2
```

**Important:** This only works if HAProxy is running **inside the Kubernetes cluster** (as a pod).

**Pros:**

- ✅ DNS names are stable (don't change on pod restart)
- ✅ Kubernetes-native
- ✅ Works with StatefulSet guarantees

**Cons:**

- ❌ Only works if HAProxy is inside the cluster
- ❌ Your current HAProxy is on your laptop (outside cluster)

---

## Recommended Solution for Your Setup

Since your HAProxy is running on your **laptop** (outside the cluster), I recommend **Option 1** with a modification:

### Modified Option 1: Use Node Affinity + NodePort

1. Ensure redis-0 (master) always runs on worker1
2. Ensure redis-1 (replica) always runs on worker2
3. Create separate NodePort services that route to specific nodes

This is already partially done with your PersistentVolumes' node affinity!

Let me create the complete solution files for you.

---

## Quick Test to Verify Current Behavior

```bash
# Test multiple times to see the load balancing
for i in {1..10}; do
  echo "Attempt $i:"
  redis-cli -h localhost -p 6379 SET test$i "value$i" 2>&1 | grep -E "OK|READONLY"
done
```

You should see a mix of `OK` and `READONLY` errors, confirming the load balancing issue.

---

## Summary

The root cause is:

- **Kubernetes NodePort Service** (`redis-nodeport`) has selector `app: redis`
- This selector matches **both** redis-0 (master) and redis-1 (replica)
- Kubernetes load balances between them randomly
- When write hits replica → `READONLY` error
- When write hits master → `OK`

The solution is to create **separate services** that target specific pods or use **pod-specific DNS names**.
