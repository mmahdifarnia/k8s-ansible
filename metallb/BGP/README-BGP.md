# MetalLB BGP Configuration Guide

This guide covers the BGP (Border Gateway Protocol) configuration for MetalLB on your Vagrant Kubernetes cluster.

## Overview

BGP mode uses standard BGP routing protocol to advertise LoadBalancer IPs to external routers. This provides true Layer 3 load balancing with ECMP (Equal-Cost Multi-Path) support.

### How BGP Mode Works

1. MetalLB speakers on each node establish BGP sessions with external router(s)
2. When a LoadBalancer service is created, speakers advertise `/32` routes to the service IP
3. External routers learn the routes and install them in their routing tables
4. Traffic is distributed across multiple nodes using ECMP
5. Routers automatically handle failover by withdrawing routes from failed nodes

### Advantages

- **True load balancing**: Traffic distributed across multiple nodes via ECMP
- **Works across subnets**: Routes can be propagated across Layer 3 boundaries
- **Scalable**: Integrates with existing BGP infrastructure
- **Fast failover**: Immediate route withdrawal on node failure
- **Production-ready**: Used in enterprise and cloud environments

### Limitations

- **Requires BGP router**: Need external BGP-capable router or software router
- **More complex**: Requires BGP knowledge and configuration
- **AS numbers**: Need to assign AS numbers
- **Router setup**: External router must be configured

## Prerequisites

- Kubernetes cluster running on Vagrant
- kubectl configured to access your cluster
- Nodes accessible from host (192.168.56.x range)
- **BGP router** on host machine (e.g., BIRD, FRR, Quagga)
- Basic understanding of BGP concepts (AS numbers, peers, routes)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Host Machine                         │
│                  (192.168.56.1)                         │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │          BIRD BGP Router (AS 64513)              │  │
│  │  - Receives /32 routes from MetalLB              │  │
│  │  - Installs routes in kernel routing table       │  │
│  └──────────────────────────────────────────────────┘  │
└───────────┬──────────────┬──────────────┬──────────────┘
            │              │              │
         BGP Session    BGP Session   BGP Session
         Port 179       Port 179      Port 179
            │              │              │
    ┌───────▼──────┐┌──────▼──────┐┌─────▼───────┐
    │   Master     ││   Worker1   ││   Worker2   │
    │  .110        ││   .111      ││   .112      │
    │              ││             ││             │
    │  MetalLB     ││  MetalLB    ││  MetalLB    │
    │  Speaker     ││  Speaker    ││  Speaker    │
    │  (AS 64512)  ││  (AS 64512) ││  (AS 64512) │
    └──────────────┘└─────────────┘└─────────────┘
            │              │              │
            └──────────────┴──────────────┘
                           │
                    Advertise /32
                 192.168.56.200/32
                           │
                    ┌──────▼──────┐
                    │   Service   │
                    │ (ClusterIP) │
                    └─────────────┘
```

## Configuration Files

### Required Files

```
metallb/
├── metallb-install.yaml         # MetalLB installation manifest
├── ipaddresspool.yaml           # IP address pool configuration
├── BGP/BGPPeer.yml                  # BGP peer configuration
├── BGP/BGPAdvertisement.yml         # BGP advertisement configuration
├── bird.conf                    # BIRD router configuration (for host)
├── nginx-deployment.yaml        # Test application (optional)
└── loadbalancer-service.yaml    # LoadBalancer service (optional)
```

## Installation Steps

### Part 1: Setup BGP Router on Host

MetalLB needs a BGP router to peer with. We'll use BIRD (BIRD Internet Routing Daemon).

#### 1. Install BIRD

On your host machine (Fedora):

```bash
sudo dnf install bird
```

Or on Ubuntu/Debian:

```bash
sudo apt install bird
```

#### 2. Configure BIRD

Copy the provided configuration:

```bash
sudo cp bird.conf /etc/bird.conf
```

**File**: `bird.conf` (BIRD 3.x syntax)

```conf
# BIRD BGP Router Configuration for MetalLB (BIRD 3.x)
log syslog all;

router id 192.168.56.1;

# Define separate BGP protocol instances for each node
# Each BGP instance can only have ONE neighbor

protocol bgp metallb_master {
    local as 64513;
    neighbor 192.168.56.110 as 64512;
    
    ipv4 {
        import all;
        export none;
    };
}

protocol bgp metallb_worker1 {
    local as 64513;
    neighbor 192.168.56.111 as 64512;
    
    ipv4 {
        import all;
        export none;
    };
}

protocol bgp metallb_worker2 {
    local as 64513;
    neighbor 192.168.56.112 as 64512;
    
    ipv4 {
        import all;
        export none;
    };
}

# Kernel protocol to install routes in system routing table
protocol kernel {
    ipv4 {
        import all;
        export all;
    };
}

# Device protocol for interface detection
protocol device {
}

# Direct protocol for directly connected networks
protocol direct {
    ipv4;
}
```

#### 3. Test BIRD Configuration

```bash
# Test configuration syntax
sudo bird -p -c /etc/bird.conf

# Should return with no errors
```

#### 4. Configure Firewall

Add the VirtualBox network interface to the trusted zone:

```bash
# Add vboxnet0 to trusted zone
sudo firewall-cmd --zone=trusted --add-interface=vboxnet0 --permanent

# Reload firewall
sudo firewall-cmd --reload

# Verify
sudo firewall-cmd --get-zone-of-interface=vboxnet0
```

Alternatively, you can open just port 179:

```bash
sudo firewall-cmd --zone=public --add-port=179/tcp --permanent
sudo firewall-cmd --reload
```

#### 5. Start BIRD Service

```bash
# Enable and start BIRD
sudo systemctl enable bird
sudo systemctl start bird

# Check status
sudo systemctl status bird
```

Expected output:
```
● bird.service - BIRD Internet Routing Daemon
     Loaded: loaded
     Active: active (running)
```

#### 6. Verify BIRD is Listening

```bash
sudo ss -tlnp | grep :179
```

Expected output:
```
LISTEN 0  8  0.0.0.0:179  0.0.0.0:*  users:(("bird",pid=XXXXX,fd=12))
```

### Part 2: Configure MetalLB

#### 1. Install MetalLB

```bash
kubectl apply -f metallb-install.yaml
```

Wait for pods to be ready:

```bash
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=metallb -n metallb-system --timeout=300s
```

#### 2. Configure IP Address Pool

**File**: `ipaddresspool.yaml`

```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.56.200-192.168.56.210
```

Apply:

```bash
kubectl apply -f ipaddresspool.yaml
```

#### 3. Configure BGP Peer

**File**: `BGPPeer.yml`

```yaml
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: my-peer
  namespace: metallb-system
spec:
  myASN: 64512        # MetalLB's AS number
  peerASN: 64513      # Router's AS number (must match bird.conf)
  peerAddress: 192.168.56.1  # Host IP (router address)
```

Apply:

```bash
kubectl apply -f BGPPeer.yml
```

#### 4. Configure BGP Advertisement

**File**: `BGPAdvertisement.yml`

```yaml
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: bgp-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
  aggregationLength: 32      # Advertise /32 routes
  communities:
  - 64512:100                # BGP community (optional)
```

Apply:

```bash
kubectl apply -f BGPAdvertisement.yml
```

#### 5. Deploy Test Application (Optional)

```bash
kubectl apply -f nginx-deployment.yaml
kubectl apply -f nginx-clusterip.yaml
kubectl apply -f loadbalancer-service.yaml
```

## Verification

### 1. Check MetalLB Status

```bash
# Check all MetalLB resources
kubectl get all -n metallb-system

# Check BGP configuration
kubectl get bgppeer,bgpadvertisement,ipaddresspool -n metallb-system
```

### 2. Check BGP Sessions from MetalLB Side

```bash
# Check speaker logs for BGP session establishment
kubectl logs -n metallb-system -l component=speaker | grep -i bgp
```

Look for:
```
"msg":"BGP session established"
```

### 3. Check BGP Sessions from BIRD Side

```bash
# Show all protocols
sudo birdc show protocols

# Expected output:
# Name            Proto      Table      State  Since         Info
# metallb_master  BGP        ---        up     HH:MM:SS      Established
# metallb_worker1 BGP        ---        up     HH:MM:SS      Established
# metallb_worker2 BGP        ---        up     HH:MM:SS      Established
```

### 4. Check BGP Routes

```bash
# Show all routes learned via BGP
sudo birdc show route

# You should see:
# 192.168.56.200/32 via 192.168.56.111 on vboxnet0 [AS64512i]
```

### 5. Check Kernel Routes

```bash
# Check if route is installed in kernel
ip route show | grep 192.168.56.200

# Expected output:
# 192.168.56.200 via 192.168.56.111 dev vboxnet0 proto bird metric 32
```

### 6. Check LoadBalancer Service

```bash
kubectl get svc nginx-loadbalancer -n metallb-system
```

Expected:
```
NAME                 TYPE           EXTERNAL-IP      PORT(S)
nginx-loadbalancer   LoadBalancer   192.168.56.200   8080:30000/TCP
```

### 7. Test Connectivity

```bash
curl http://192.168.56.200:8080
```

Expected: nginx welcome page

## BGP Session Details

### View Detailed BGP Session Info

```bash
# Detailed info for master node session
sudo birdc show protocols all metallb_master

# Check routes from specific peer
sudo birdc show route protocol metallb_master
```

### Monitor BGP Sessions

```bash
# Watch BGP protocol status
watch -n 2 'sudo birdc show protocols'

# Monitor MetalLB speaker logs in real-time
kubectl logs -n metallb-system -l component=speaker -f
```

## Configuration Details

### AS Numbers

- **Private AS Range**: 64512-65534 (used in this configuration)
- **MetalLB AS**: 64512 (configured in `BGPPeer.yml`)
- **Router AS**: 64513 (configured in `bird.conf`)

For production, you might use public AS numbers if available.

### BGP Advertisement Options

```yaml
apiVersion: metallb.io/v1beta1
kind: BGPAdvertisement
metadata:
  name: bgp-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
  - default-pool
  
  # Advertise /32 routes (default)
  aggregationLength: 32
  
  # Or aggregate to /24
  # aggregationLength: 24
  
  # BGP communities for policy-based routing
  communities:
  - 64512:100
  
  # Advertise only from specific nodes
  nodeSelectors:
  - matchLabels:
      node-role: edge
  
  # BGP peers to advertise to (if multiple peers configured)
  peers:
  - my-peer
```

### Advanced BGP Peer Options

```yaml
apiVersion: metallb.io/v1beta2
kind: BGPPeer
metadata:
  name: my-peer
  namespace: metallb-system
spec:
  myASN: 64512
  peerASN: 64513
  peerAddress: 192.168.56.1
  
  # Optional: Source address for BGP connection
  sourceAddress: 192.168.56.110
  
  # Optional: Router ID
  routerID: 192.168.56.110
  
  # Optional: Hold time (seconds)
  holdTime: 180s
  
  # Optional: Keepalive time (seconds)
  keepaliveTime: 60s
  
  # Optional: Multi-hop BGP
  ebgpMultiHop: true
  
  # Optional: BFD profile
  bfdProfile: default
  
  # Optional: Password for BGP authentication
  password: "secretpassword"
```

## Troubleshooting

### BGP Sessions Not Establishing

**Problem**: BGP sessions show "Active" or "Connect" instead of "Established".

**Check from BIRD side**:

```bash
sudo birdc show protocols
```

If you see "Connection refused":

1. **Check firewall**:
```bash
sudo firewall-cmd --list-all
sudo firewall-cmd --zone=trusted --add-interface=vboxnet0 --permanent
sudo firewall-cmd --reload
```

2. **Check BIRD is listening**:
```bash
sudo ss -tlnp | grep :179
```

3. **Check BIRD logs**:
```bash
sudo journalctl -u bird -n 50
```

Common BIRD errors:

- **"Only one neighbor per BGP instance is allowed"**: BIRD 3.x requires separate protocol blocks for each neighbor
- **Syntax error**: Test config with `sudo bird -p -c /etc/bird.conf`

**Check from MetalLB side**:

```bash
kubectl logs -n metallb-system -l component=speaker | grep error
```

Common errors:

- **"no route to host"**: Firewall blocking port 179
- **"connection refused"**: BIRD not running or not listening
- **"connection timeout"**: Network connectivity issue

### Routes Not Appearing

**Problem**: BGP sessions established but routes not appearing.

1. **Check BGP advertisements**:
```bash
kubectl get bgpadvertisement -n metallb-system -o yaml
```

2. **Check if service has IP assigned**:
```bash
kubectl get svc -n metallb-system
```

3. **Check speaker logs**:
```bash
kubectl logs -n metallb-system -l component=speaker | grep announce
```

Should see:
```
"msg":"service has IP, announcing"
```

4. **Check BIRD routes**:
```bash
sudo birdc show route
```

### Service Not Reachable

**Problem**: Routes exist but service not accessible.

1. **Verify route in kernel**:
```bash
ip route show | grep 192.168.56.200
```

2. **Test routing**:
```bash
traceroute 192.168.56.200
```

3. **Check service endpoints**:
```bash
kubectl get endpoints nginx-loadbalancer -n metallb-system
```

4. **Test from node directly**:
```bash
kubectl run test --rm -it --image=busybox -- wget -O- http://192.168.56.200:8080
```

### BIRD Configuration Issues

**Problem**: BIRD won't start or has errors.

1. **Check syntax**:
```bash
sudo bird -p -c /etc/bird.conf
```

2. **Check BIRD logs**:
```bash
sudo journalctl -u bird --no-pager -n 50
```

3. **Common issues**:
   - Multiple neighbors in one protocol block (BIRD 3.x)
   - Wrong AS numbers
   - Syntax errors (missing semicolons, braces)

### Node Excluded from External Load Balancers

**Problem**: Speaker logs show "node has labeled 'node.kubernetes.io/exclude-from-external-load-balancers'".

**Solution**:

```bash
# Remove the taint/label from nodes
kubectl taint nodes --all node.kubernetes.io/exclude-from-external-load-balancers-
```

## Switching from L2 to BGP

If you're switching from L2 mode:

1. **Delete L2 advertisement**:
```bash
kubectl delete -f l2advertisement.yaml
```

2. **Setup BIRD router** (see Part 1 above)

3. **Apply BGP configuration**:
```bash
kubectl apply -f BGPPeer.yml
kubectl apply -f BGPAdvertisement.yml
```

The `ipaddresspool.yaml` remains the same.

## Switching from BGP to L2

If you want to switch back to L2 mode:

1. **Delete BGP configuration**:
```bash
kubectl delete -f BGPAdvertisement.yml
kubectl delete -f BGPPeer.yml
```

2. **Apply L2 advertisement**:
```bash
kubectl apply -f l2advertisement.yaml
```

3. **Stop BIRD (optional)**:
```bash
sudo systemctl stop bird
sudo systemctl disable bird
```

## Uninstallation

### Remove MetalLB BGP Configuration

```bash
# Remove test application
kubectl delete -f loadbalancer-service.yaml
kubectl delete -f nginx-clusterip.yaml
kubectl delete -f nginx-deployment.yaml

# Remove BGP configuration
kubectl delete -f BGPAdvertisement.yml
kubectl delete -f BGPPeer.yml
kubectl delete -f ipaddresspool.yaml

# Remove MetalLB (optional)
kubectl delete -f metallb-install.yaml
```

### Remove BIRD Router

```bash
# Stop BIRD
sudo systemctl stop bird
sudo systemctl disable bird

# Remove configuration
sudo rm /etc/bird.conf

# Remove from firewall (if added to trusted zone)
sudo firewall-cmd --zone=trusted --remove-interface=vboxnet0 --permanent
sudo firewall-cmd --reload
```

## Best Practices

1. **AS Number Planning**: Use private AS numbers (64512-65534) for lab environments
2. **BGP Authentication**: Use password authentication in production
3. **Monitoring**: Monitor BGP session state and route advertisements
4. **Graceful Restart**: Enable BGP graceful restart for maintenance
5. **Route Filtering**: Use BGP communities for policy-based routing
6. **Documentation**: Document your BGP topology and AS numbers
7. **Testing**: Test failover scenarios before production use

## Comparison: L2 vs BGP

| Feature | Layer 2 | BGP |
|---------|---------|-----|
| Setup Complexity | Simple | Moderate |
| External Dependencies | None | BGP Router Required |
| Load Distribution | Single Node | Multiple Nodes (ECMP) |
| Failover Time | ~10 seconds | < 1 second |
| Network Scope | Single Subnet | Multi-Subnet |
| Scalability | Limited | High |
| Production Use | Small Deployments | Enterprise/Cloud |

## Additional Resources

- [MetalLB Official Documentation](https://metallb.universe.tf/)
- [BGP Configuration Guide](https://metallb.universe.tf/configuration/_advanced_bgp_configuration/)
- [BIRD Documentation](https://bird.network.cz/?get_doc)
- [BGP Tutorial](https://www.noction.com/blog/bgp-essentials)

## Appendix: BIRD Commands Reference

```bash
# Show all protocols
sudo birdc show protocols

# Show detailed protocol info
sudo birdc show protocols all metallb_master

# Show routing table
sudo birdc show route

# Show routes from specific protocol
sudo birdc show route protocol metallb_master

# Show BGP specific info
sudo birdc show route where bgp_path ~ [* 64512 *]

# Show protocol statistics
sudo birdc show protocols stats

# Reload configuration
sudo birdc configure

# Restart protocol
sudo birdc restart metallb_master

# Enable debug
sudo birdc debug all

# Show memory usage
sudo birdc show memory
```

