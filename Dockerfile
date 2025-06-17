# Build stage
FROM node:20.19.0-alpine3.21 AS builder

# Install build dependencies
RUN apk add --no-cache \
    python3 \
    py3-pip \
    gcc \
    python3-dev \
    musl-dev \
    curl \
    git \
    build-base

# Install n8n
ARG N8N_VERSION=latest
ENV NODE_ENV=production

RUN set -eux; \
    npm install -g --omit=dev n8n@${N8N_VERSION} --ignore-scripts && \
    npm install -g semver && \
    npm rebuild --prefix=/usr/local/lib/node_modules/n8n sqlite3 && \
    find /usr/local/lib/node_modules/n8n -type f -name "*.ts" -o -name "*.js.map" -o -name "*.vue" | xargs rm -f && \
    rm -rf /root/.npm

# Runtime stage
FROM node:20.19.0-alpine3.21

# Install runtime dependencies
RUN apk add --no-cache \
    python3 \
    py3-pip \
    curl \
    ffmpeg \
    py3-numpy \
    py3-pillow \
    git \
    tini

# Copy n8n from builder stage
COPY --from=builder /usr/local/lib/node_modules/n8n /usr/local/lib/node_modules/n8n
COPY --from=builder /usr/local/bin/n8n /usr/local/bin/n8n

# Copy application files
COPY n8n-task-runners.json /etc/n8n-task-runners.json
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Clean up temporary files
RUN rm -rf /tmp/v8-compile-cache*

# Set environment variables
ENV NODE_ICU_DATA=/usr/local/lib/node_modules/full-icu
ENV NODE_ENV=production
ENV N8N_RELEASE_TYPE=stable
ENV SHELL=/bin/sh

# Install task runner launcher
ARG TARGETPLATFORM=linux/amd64
ARG LAUNCHER_VERSION=1.1.1
RUN if [ "$TARGETPLATFORM" = "linux/amd64" ]; then \
        curl -L -o /usr/local/bin/task-runner-launcher https://github.com/n8n-io/task-runner-launcher/releases/download/v${LAUNCHER_VERSION}/task-runner-launcher_linux_amd64 && \
        chmod +x /usr/local/bin/task-runner-launcher; \
    fi

# Install Python dependencies and MCP tools
RUN python3 -m venv /opt/venv
ENV PATH=/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Install Python and Node.js packages
RUN /opt/venv/bin/pip install --no-cache-dir moviepy==1.0.3 mcp==1.0.0 && \
    npm install -g @modelcontextprotocol/sdk

# Create directories and install MCP servers
RUN mkdir -p /usr/local/scripts /opt/mcp-servers && \
    cd /opt/mcp-servers && \
    git clone https://github.com/modelcontextprotocol/servers.git && \
    chown -R node:node /opt/venv /opt/mcp-servers /usr/local/scripts

# Add MCP server examples to PATH
ENV MCP_SERVERS_PATH=/opt/mcp-servers/servers
ENV PATH=/opt/mcp-servers/servers/bin:$PATH

# Final setup
RUN mkdir -p /home/node/.n8n && chown -R node:node /home/node

# Add labels
LABEL org.opencontainers.image.title="n8n"
LABEL org.opencontainers.image.description="Workflow Automation Tool"
LABEL org.opencontainers.image.source="https://github.com/n8n-io/n8n"
LABEL org.opencontainers.image.url="https://n8n.io"
LABEL org.opencontainers.image.version="1.90.2"

# Expose port
EXPOSE 5678

# Switch to non-root user
USER node
WORKDIR /home/node
ENTRYPOINT ["tini", "--", "/usr/local/bin/docker-entrypoint.sh"]