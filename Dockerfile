FROM node:20.19.0-alpine3.21

# Install system dependencies
RUN apk add --no-cache \
    python3 \
    py3-pip \
    gcc \
    python3-dev \
    musl-dev \
    curl \
    ffmpeg \
    py3-numpy \
    py3-pillow \
    git \
    build-base \
    tini

# Copy additional files early for caching
COPY n8n-task-runners.json /etc/n8n-task-runners.json
COPY docker-entrypoint.sh /usr/local/bin/
COPY / /
RUN rm -rf /tmp/v8-compile-cache*

ENV NODE_ICU_DATA=/usr/local/lib/node_modules/full-icu
EXPOSE 5678

# Install n8n
ARG N8N_VERSION=latest
RUN if [ -z "$N8N_VERSION" ] ; then echo "The N8N_VERSION argument is missing!" ; exit 1; fi

LABEL org.opencontainers.image.title="n8n"
LABEL org.opencontainers.image.description="Workflow Automation Tool"
LABEL org.opencontainers.image.source="https://github.com/n8n-io/n8n"
LABEL org.opencontainers.image.url="https://n8n.io"
LABEL org.opencontainers.image.version="1.90.2"

ENV N8N_VERSION=latest
ENV NODE_ENV=production
ENV N8N_RELEASE_TYPE=stable

RUN set -eux; \
    npm install -g --omit=dev n8n@${N8N_VERSION} --ignore-scripts && \
    npm rebuild --prefix=/usr/local/lib/node_modules/n8n sqlite3 && \
    find /usr/local/lib/node_modules/n8n -type f -name "*.ts" -o -name "*.js.map" -o -name "*.vue" | xargs rm -f && \
    rm -rf /root/.npm

# Install task runner launcher
ARG TARGETPLATFORM=linux/amd64
ARG LAUNCHER_VERSION=1.1.1
RUN if [[ "$TARGETPLATFORM" = "linux/amd64" ]]; then \
        curl -L -o /usr/local/bin/task-runner-launcher https://github.com/n8n-io/task-runner-launcher/releases/download/v${LAUNCHER_VERSION}/task-runner-launcher_linux_amd64 && \
        chmod +x /usr/local/bin/task-runner-launcher; \
    fi

# Install Python dependencies and MCP tools
USER root
RUN python3 -m venv /opt/venv
ENV PATH=/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Install Python and Node.js packages
RUN /opt/venv/bin/pip install --no-cache-dir moviepy mcp && \
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
COPY docker-entrypoint.sh /
RUN mkdir -p /home/node/.n8n && chown -R node:node /home/node
ENV SHELL=/bin/sh

USER node
WORKDIR /home/node
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]