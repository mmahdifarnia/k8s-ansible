#!/bin/sh
set -e

# Ensure log directory exists and has proper permissions
mkdir -p /var/log/haproxy
chown -R haproxy:haproxy /var/log/haproxy

# Start HAProxy in foreground and redirect logs to both stdout and file
exec haproxy -f /usr/local/etc/haproxy/haproxy.cfg 2>&1 | tee -a /var/log/haproxy/haproxy.log
