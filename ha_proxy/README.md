# HAProxy Load Balancer

This directory contains HAProxy configuration for load balancing Redis and Kafka services running on Kubernetes nodes.

## Features

- **Redis Read/Write Splitting**:
  - Write operations (Master) on port 6379
  - Read operations (Replica) on port 6380
- **Kafka Load Balancing** on port 9092
- **Statistics Dashboard** on port 8404
- Health checks for backend services
- Automatic failover
- Optimized for Redis master-replica architecture

## Quick Start

### 1. Update Backend Server IPs

Edit `haproxy.cfg` and replace the IP addresses with your actual Kubernetes node IPs:

```cfg
# Redis write backend (Master)
server redis1 192.168.56.111:30917 check inter 5s fall 3 rise 2

# Redis read backend (Replica)
server redis2 192.168.56.112:30917 check inter 5s fall 3 rise 2

# Kafka backend
server kafka1 192.168.56.111:30092 check inter 10s fall 3 rise 2
server kafka2 192.168.56.112:30092 check inter 10s fall 3 rise 2
```

### 2. Build and Run

```bash
# Build the Docker image
docker-compose build

# Start HAProxy
docker-compose up -d

# View logs
docker-compose logs -f

# Stop HAProxy
docker-compose down
```

### 3. Access Statistics Dashboard

Open your browser and navigate to:

```
http://localhost:8404/stats
```

This dashboard shows:

- Backend server status
- Connection statistics
- Health check results
- Traffic metrics

## Testing

### Test Redis Connection

**Write Operations (Master - Port 6379):**

```bash
# Test connection
redis-cli -h localhost -p 6379 ping

# Write data
redis-cli -h localhost -p 6379 SET mykey "Hello Redis"
redis-cli -h localhost -p 6379 HSET user:1 name "John" email "john@example.com"

# Verify write
redis-cli -h localhost -p 6379 GET mykey
```

**Read Operations (Replica - Port 6380):**

```bash
# Test connection
redis-cli -h localhost -p 6380 ping

# Read data
redis-cli -h localhost -p 6380 GET mykey
redis-cli -h localhost -p 6380 HGETALL user:1

# List all keys
redis-cli -h localhost -p 6380 KEYS "*"
```

**Important Notes:**

- All **write commands** (SET, HSET, DEL, etc.) should use port **6379** (Master)
- All **read commands** (GET, HGETALL, KEYS, etc.) should use port **6380** (Replica)
- This ensures optimal performance and reduces load on the master

### Test Kafka Connection

```bash
# Check if port is accessible
nc -zv localhost 9092

# Using kafka console producer (if you have Kafka tools installed)
kafka-console-producer --broker-list localhost:9092 --topic test
```

### Check HAProxy Health

```bash
curl http://localhost:8404/health
```

## Configuration Details

### Redis Read/Write Splitting Architecture

**Write Backend (Master):**

- Port: 6379
- Routes to: redis1 (192.168.56.111:30917)
- Handles: SET, HSET, DEL, INCR, LPUSH, SADD, ZADD, etc.
- No load balancing (single master)

**Read Backend (Replica):**

- Port: 6380
- Routes to: redis2 (192.168.56.112:30917)
- Handles: GET, HGETALL, KEYS, LRANGE, SMEMBERS, ZRANGE, etc.
- Can be scaled with multiple replicas using `leastconn` algorithm

### Load Balancing Algorithm

- **Kafka**: Least Connections (`leastconn`)
- Best for long-lived connections

### Health Checks

**Redis:**

- Sends `PING` command
- Expects `+PONG` response
- Check interval: 5 seconds
- Fail threshold: 3 consecutive failures
- Rise threshold: 2 consecutive successes

**Kafka:**

- TCP connection check
- Check interval: 10 seconds
- Fail threshold: 3 consecutive failures
- Rise threshold: 2 consecutive successes

### Timeouts

**Redis:**

- Connect timeout: 3 seconds
- Client timeout: 30 seconds
- Server timeout: 30 seconds

**Kafka:**

- Connect timeout: 5 seconds
- Client timeout: 60 seconds
- Server timeout: 60 seconds

## Logs

Logs are stored in the `./logs` directory (mounted as volume) and also available via Docker logs.

### View Logs

**Option 1: Use the log viewer script (recommended)**

```bash
./view-logs.sh
```

**Option 2: View file logs directly**

```bash
# Live tail
tail -f logs/haproxy.log

# Last 100 lines
tail -n 100 logs/haproxy.log

# View all logs
cat logs/haproxy.log
```

**Option 3: View Docker container logs**

```bash
# Live logs
docker-compose logs -f haproxy-loadbalancer

# Last 100 lines
docker-compose logs --tail=100 haproxy-loadbalancer
```

### Log Format

HAProxy logs include:

- Connection attempts
- Backend server health status
- Load balancing decisions
- Error messages
- Performance metrics

## Troubleshooting

### Backend servers showing as DOWN

1. Check if the backend IPs and ports are correct
2. Verify Kubernetes NodePort services are running
3. Check firewall rules
4. Review health check logs in stats dashboard

### Connection refused

1. Ensure HAProxy container is running: `docker-compose ps`
2. Check port bindings: `docker-compose port haproxy-loadbalancer 6379`
3. Verify no other service is using the same ports

### High latency

1. Check backend server health in stats dashboard
2. Review connection pool settings
3. Consider adjusting timeout values in `haproxy.cfg`

## Comparison with Nginx

HAProxy advantages:

- Better TCP load balancing performance
- More sophisticated health checks
- Built-in statistics dashboard
- Better connection management for stateful protocols
- More granular control over load balancing algorithms

## Additional Configuration

### Adding More Read Replicas

To scale read operations, add more replicas to the read backend:

```cfg
backend redis_read_backend
    mode tcp
    balance leastconn  # Distribute reads across replicas

    # ... existing config ...
    server redis2 192.168.56.112:30917 check inter 5s fall 3 rise 2
    server redis3 192.168.56.113:30917 check inter 5s fall 3 rise 2
    server redis4 192.168.56.114:30917 check inter 5s fall 3 rise 2
```

**Note:** The write backend should always point to a single master server.

### Redis Command Reference

**Write Commands (Use Port 6379 - Master):**

```bash
# String operations
redis-cli -h localhost -p 6379 SET key "value"
redis-cli -h localhost -p 6379 SETEX key 3600 "value"  # with TTL
redis-cli -h localhost -p 6379 MSET key1 "val1" key2 "val2"
redis-cli -h localhost -p 6379 INCR counter
redis-cli -h localhost -p 6379 DECR counter

# Hash operations
redis-cli -h localhost -p 6379 HSET user:1 name "John"
redis-cli -h localhost -p 6379 HMSET user:1 name "John" age "30"
redis-cli -h localhost -p 6379 HINCRBY user:1 age 1

# List operations
redis-cli -h localhost -p 6379 LPUSH mylist "item"
redis-cli -h localhost -p 6379 RPUSH mylist "item"
redis-cli -h localhost -p 6379 LPOP mylist

# Set operations
redis-cli -h localhost -p 6379 SADD myset "member"
redis-cli -h localhost -p 6379 SREM myset "member"

# Sorted Set operations
redis-cli -h localhost -p 6379 ZADD leaderboard 100 "player1"

# Delete operations
redis-cli -h localhost -p 6379 DEL key
redis-cli -h localhost -p 6379 HDEL user:1 field
```

**Read Commands (Use Port 6380 - Replica):**

```bash
# String operations
redis-cli -h localhost -p 6380 GET key
redis-cli -h localhost -p 6380 MGET key1 key2 key3
redis-cli -h localhost -p 6380 EXISTS key
redis-cli -h localhost -p 6380 TTL key

# Hash operations
redis-cli -h localhost -p 6380 HGET user:1 name
redis-cli -h localhost -p 6380 HGETALL user:1
redis-cli -h localhost -p 6380 HKEYS user:1
redis-cli -h localhost -p 6380 HVALS user:1

# List operations
redis-cli -h localhost -p 6380 LRANGE mylist 0 -1
redis-cli -h localhost -p 6380 LLEN mylist
redis-cli -h localhost -p 6380 LINDEX mylist 0

# Set operations
redis-cli -h localhost -p 6380 SMEMBERS myset
redis-cli -h localhost -p 6380 SISMEMBER myset "member"
redis-cli -h localhost -p 6380 SCARD myset

# Sorted Set operations
redis-cli -h localhost -p 6380 ZRANGE leaderboard 0 -1
redis-cli -h localhost -p 6380 ZRANK leaderboard "player1"
redis-cli -h localhost -p 6380 ZSCORE leaderboard "player1"

# Key operations
redis-cli -h localhost -p 6380 KEYS "*"
redis-cli -h localhost -p 6380 SCAN 0
redis-cli -h localhost -p 6380 TYPE key

# Info and monitoring
redis-cli -h localhost -p 6380 INFO
redis-cli -h localhost -p 6380 PING
```

### Changing Load Balancing Algorithm

Available algorithms for read replicas:

- `roundrobin` - Simple round-robin
- `leastconn` - Least connections (current for reads)
- `source` - Source IP hash (sticky sessions)
- `first` - Use first available server

Example:

```cfg
backend redis_read_backend
    balance roundrobin  # Change to round-robin
    # ... rest of config ...
```

## Security Considerations

1. **Stats Dashboard**: Consider adding authentication in production
2. **Network Isolation**: Use Docker networks to isolate services
3. **TLS/SSL**: Add SSL termination if needed
4. **Access Control**: Use firewall rules to restrict access

## References

- [HAProxy Documentation](http://www.haproxy.org/#docs)
- [HAProxy Configuration Manual](https://cbonte.github.io/haproxy-dconv/)
