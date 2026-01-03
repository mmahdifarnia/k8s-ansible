FROM nginx:alpine

# Install additional tools for health checks
RUN apk add --no-cache curl netcat-openbsd

# Copy custom nginx configuration
COPY nginx.conf /etc/nginx/nginx.conf

# Create log directory
RUN mkdir -p /var/log/nginx

CMD ["nginx", "-g", "daemon off;"]