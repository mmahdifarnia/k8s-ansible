FROM haproxy:2.9-alpine

# Switch to root to install packages
USER root

# Install additional tools for health checks and debugging
RUN apk add --no-cache curl netcat-openbsd

# Copy HAProxy configuration and entrypoint script
COPY haproxy.cfg /usr/local/etc/haproxy/haproxy.cfg
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Make entrypoint executable
RUN chmod +x /usr/local/bin/entrypoint.sh

# Create log directory with proper permissions
RUN mkdir -p /var/log/haproxy && \
    chown -R haproxy:haproxy /var/log/haproxy

# Expose ports
# Redis load balancer
EXPOSE 6379
# Kafka load balancer
EXPOSE 9092
# HAProxy stats page
EXPOSE 8404

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8404/health || exit 1

# Use entrypoint script to handle logging
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

