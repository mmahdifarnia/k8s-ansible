# Redis Read/Write Splitting Configuration

## Overview

This HAProxy configuration implements **Redis read/write splitting** to optimize performance by routing:

- **Write operations** → Redis Master (redis1)
- **Read operations** → Redis Replica (redis2)

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       ├─────────────────────────────────────┐
       │                                     │
       │ Port 6379 (Writes)                  │ Port 6380 (Reads)
       │                                     │
┌──────▼──────────┐                  ┌──────▼──────────┐
│  HAProxy        │                  │  HAProxy        │
│  Write Frontend │                  │  Read Frontend  │
└──────┬──────────┘                  └──────┬──────────┘
       │                                     │
       │                                     │
┌──────▼──────────┐                  ┌──────▼──────────┐
│  redis1         │                  │  redis2         │
│  (Master)       │ ───replication──>│  (Replica)      │
│  192.168.56.111 │                  │  192.168.56.112 │
└─────────────────┘                  └─────────────────┘
```

## Port Configuration

| Port | Purpose          | Backend             | Server           |
| ---- | ---------------- | ------------------- | ---------------- |
| 6379 | Write Operations | redis_write_backend | redis1 (Master)  |
| 6380 | Read Operations  | redis_read_backend  | redis2 (Replica) |
| 8404 | HAProxy Stats    | -                   | -                |

## Usage Examples

### Write Operations (Port 6379)

All commands that **modify data** should use port **6379**:

```bash
# String operations
redis-cli -h localhost -p 6379 SET mykey "myvalue"
redis-cli -h localhost -p 6379 INCR counter
redis-cli -h localhost -p 6379 SETEX session:123 3600 "user_data"

# Hash operations
redis-cli -h localhost -p 6379 HSET user:1000 name "Alice" email "alice@example.com"
redis-cli -h localhost -p 6379 HINCRBY user:1000 login_count 1

# List operations
redis-cli -h localhost -p 6379 LPUSH notifications "New message"
redis-cli -h localhost -p 6379 RPUSH queue "task1"

# Set operations
redis-cli -h localhost -p 6379 SADD tags "redis" "haproxy" "kubernetes"

# Sorted Set operations
redis-cli -h localhost -p 6379 ZADD leaderboard 1500 "player1"

# Delete operations
redis-cli -h localhost -p 6379 DEL old_key
redis-cli -h localhost -p 6379 EXPIRE mykey 300
```

### Read Operations (Port 6380)

All commands that **only read data** should use port **6380**:

```bash
# String operations
redis-cli -h localhost -p 6380 GET mykey
redis-cli -h localhost -p 6380 MGET key1 key2 key3
redis-cli -h localhost -p 6380 EXISTS mykey

# Hash operations
redis-cli -h localhost -p 6380 HGET user:1000 name
redis-cli -h localhost -p 6380 HGETALL user:1000
redis-cli -h localhost -p 6380 HKEYS user:1000

# List operations
redis-cli -h localhost -p 6380 LRANGE notifications 0 -1
redis-cli -h localhost -p 6380 LLEN queue

# Set operations
redis-cli -h localhost -p 6380 SMEMBERS tags
redis-cli -h localhost -p 6380 SISMEMBER tags "redis"

# Sorted Set operations
redis-cli -h localhost -p 6380 ZRANGE leaderboard 0 10 WITHSCORES
redis-cli -h localhost -p 6380 ZRANK leaderboard "player1"

# Key operations
redis-cli -h localhost -p 6380 KEYS "user:*"
redis-cli -h localhost -p 6380 SCAN 0 MATCH "session:*"
redis-cli -h localhost -p 6380 TTL mykey

# Monitoring
redis-cli -h localhost -p 6380 INFO replication
redis-cli -h localhost -p 6380 PING
```

## Quick Reference: Write vs Read Commands

### Write Commands (Port 6379)

- `SET`, `SETEX`, `SETNX`, `MSET`
- `HSET`, `HMSET`, `HINCRBY`, `HDEL`
- `LPUSH`, `RPUSH`, `LPOP`, `RPOP`, `LSET`
- `SADD`, `SREM`, `SPOP`
- `ZADD`, `ZREM`, `ZINCRBY`
- `DEL`, `EXPIRE`, `EXPIREAT`, `PERSIST`
- `INCR`, `DECR`, `INCRBY`, `DECRBY`
- `APPEND`, `RENAME`

### Read Commands (Port 6380)

- `GET`, `MGET`, `STRLEN`
- `HGET`, `HGETALL`, `HKEYS`, `HVALS`, `HLEN`
- `LRANGE`, `LLEN`, `LINDEX`
- `SMEMBERS`, `SISMEMBER`, `SCARD`, `SINTER`, `SUNION`
- `ZRANGE`, `ZRANK`, `ZSCORE`, `ZCARD`, `ZCOUNT`
- `EXISTS`, `TTL`, `TYPE`
- `KEYS`, `SCAN`
- `INFO`, `PING`, `DBSIZE`

## Benefits

1. **Reduced Master Load**: Read operations don't burden the master
2. **Better Performance**: Reads can be distributed across multiple replicas
3. **Scalability**: Easy to add more read replicas
4. **High Availability**: Master failure doesn't affect read operations
5. **Clear Separation**: Application logic clearly separates read/write concerns

## Application Integration

### Python Example

```python
import redis

# Create two connection pools
write_pool = redis.ConnectionPool(host='localhost', port=6379, db=0)
read_pool = redis.ConnectionPool(host='localhost', port=6380, db=0)

write_client = redis.Redis(connection_pool=write_pool)
read_client = redis.Redis(connection_pool=read_pool)

# Write operation
write_client.set('user:1000:name', 'Alice')

# Read operation
name = read_client.get('user:1000:name')
```

### Node.js Example

```javascript
const redis = require("redis");

// Create two clients
const writeClient = redis.createClient({ host: "localhost", port: 6379 });
const readClient = redis.createClient({ host: "localhost", port: 6380 });

// Write operation
await writeClient.set("user:1000:name", "Alice");

// Read operation
const name = await readClient.get("user:1000:name");
```

### Go Example

```go
package main

import (
    "github.com/go-redis/redis/v8"
    "context"
)

var ctx = context.Background()

func main() {
    // Create two clients
    writeClient := redis.NewClient(&redis.Options{
        Addr: "localhost:6379",
    })

    readClient := redis.NewClient(&redis.Options{
        Addr: "localhost:6380",
    })

    // Write operation
    writeClient.Set(ctx, "user:1000:name", "Alice", 0)

    // Read operation
    name, _ := readClient.Get(ctx, "user:1000:name").Result()
}
```

## Deployment

### 1. Ensure Redis Replication is Configured

Make sure redis2 is configured as a replica of redis1:

```bash
# On redis2, check replication status
redis-cli -h 192.168.56.112 -p 30917 INFO replication

# Should show:
# role:slave
# master_host:192.168.56.111
```

### 2. Restart HAProxy

```bash
cd /home/mahdi/Tutorial/Vagrant/ha_proxy
docker-compose down
docker-compose up -d
```

### 3. Verify Configuration

```bash
# Check HAProxy is running
docker-compose ps

# Test write port
redis-cli -h localhost -p 6379 PING

# Test read port
redis-cli -h localhost -p 6380 PING

# View stats dashboard
open http://localhost:8404/stats
```

### 4. Test Read/Write Splitting

```bash
# Write to master
redis-cli -h localhost -p 6379 SET test_key "Hello from master"

# Wait a moment for replication (usually < 1ms)
sleep 1

# Read from replica
redis-cli -h localhost -p 6380 GET test_key
# Should return: "Hello from master"
```

## Monitoring

### HAProxy Stats Dashboard

Access the dashboard at: http://localhost:8404/stats

Monitor:

- **redis_write_backend**: Should show redis1 as UP
- **redis_read_backend**: Should show redis2 as UP
- Connection counts for each backend
- Health check status

### Redis Replication Lag

Check replication lag on the replica:

```bash
redis-cli -h localhost -p 6380 INFO replication | grep master_last_io_seconds_ago
```

A value of 0-1 seconds is normal.

## Troubleshooting

### Writes Failing

```bash
# Check master is accessible
redis-cli -h 192.168.56.111 -p 30917 PING

# Check HAProxy write backend status
curl http://localhost:8404/stats | grep redis_write
```

### Reads Returning Stale Data

```bash
# Check replication status
redis-cli -h 192.168.56.112 -p 30917 INFO replication

# Check replication lag
redis-cli -h 192.168.56.112 -p 30917 INFO replication | grep master_last_io_seconds_ago
```

### Both Ports Showing Same Data

This is expected! Replication ensures both master and replica have the same data. The difference is:

- Port 6379 accepts both reads and writes
- Port 6380 only accepts reads (writes will succeed but only on the replica, not synced to master)

## Important Notes

⚠️ **Never write to the read port (6380) in production!**

- Writes to the replica won't replicate back to the master
- This creates data inconsistency
- Always use port 6379 for writes

✅ **Best Practices:**

- Use port 6379 for all write operations
- Use port 6380 for all read operations
- Monitor replication lag
- Add more replicas to scale reads
- Keep master dedicated to writes

## Scaling Reads

To add more read replicas, update `haproxy.cfg`:

```cfg
backend redis_read_backend
    mode tcp
    balance leastconn

    # ... existing config ...
    server redis2 192.168.56.112:30917 check inter 5s fall 3 rise 2
    server redis3 192.168.56.113:30917 check inter 5s fall 3 rise 2
    server redis4 192.168.56.114:30917 check inter 5s fall 3 rise 2
```

Then restart HAProxy:

```bash
docker-compose restart
```

## References

- [Redis Replication](https://redis.io/docs/management/replication/)
- [HAProxy Configuration](https://www.haproxy.org/download/2.8/doc/configuration.txt)
- [Redis Commands](https://redis.io/commands/)
