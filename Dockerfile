FROM alpine:3.21.3

# Install Node.js
ENV NODE_VERSION=20.19.0
RUN addgroup -g 1000 node && adduser -u 1000 -G node -s /bin/sh -D node && \
    apk add --no-cache \
        libstdc++ \
        && apk add --no-cache --virtual .build-deps \
        binutils-gold \
        curl \
        g++ \
        gcc \
        gnupg \
        libgcc \
        linux-headers \
        make \
        python3 \
        && for key in \
        4ED778F539E3634C779C87C6D7062848A1AB005C \
        141F07595B7B3FFE74309A937405533BE57C7D57 \
        74F12602B6F1C4E913FAA37AD3A89613643B6201 \
        DD792F5973C6DE52C432CBDAC77ABFA00DDBF2B7 \
        61FC681DFB92A079F1685E77973F295594EC4689 \
        8FCCA13FEF1D0C2E91008E09770F7A9A5AE15600 \
        C4F0DFFF4E8C1A8236409D08E73BC641CC11F4C8 \
        890C08DB8579162FEE0DF9DB8BEAB4DFCF555EF4 \
        C82FA3AE1CBEDC6BE46B9360C43CEC45C17AB93C \
        108F52B48DB57BB0CC439B2997B01419BD92F80A \
        A363A499291CBBC940DD62E41F10027AF002F8B0 \
        CC68F5A3106FF448322E48ED27F5E38D5B0A215F \
        ; do \
        gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" || \
        gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" ; \
        done \
        && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION.tar.xz" \
        && curl -fsSLO --compressed "https://nodejs.org/dist/v$NODE_VERSION/SHASUMS256.txt.asc" \
        && gpg --batch --decrypt --output SHASUMS256.txt SHASUMS256.txt.asc \
        && grep " node-v$NODE_VERSION.tar.xz\$" SHASUMS256.txt | sha256sum -c - \
        && tar -xf "node-v$NODE_VERSION.tar.xz" \
        && cd "node-v$NODE_VERSION" \
        && ./configure \
        && make -j$(getconf _NPROCESSORS_ONLN) V= \
        && make install \
        && apk del .build-deps \
        && cd .. \
        && rm -Rf "node-v$NODE_VERSION" \
        && rm "node-v$NODE_VERSION.tar.xz" SHASUMS256.txt.asc SHASUMS256.txt

# Install Yarn
ENV YARN_VERSION=1.22.22
RUN apk add --no-cache --virtual .build-deps-yarn curl gnupg tar \
    && export GNUPGHOME="$(mktemp -d)" \
    && for key in \
        6A010C5166006599AA17F08146C2130DFD2497F5 \
    ; do \
        gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "$key" || \
        gpg --batch --keyserver keyserver.ubuntu.com --recv-keys "$key" ; \
    done \
    && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz" \
    && curl -fsSLO --compressed "https://yarnpkg.com/downloads/$YARN_VERSION/yarn-v$YARN_VERSION.tar.gz.asc" \
    && gpg --batch --verify yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
    && mkdir -p /opt \
    && tar -xzf yarn-v$YARN_VERSION.tar.gz -C /opt/ \
    && ln -s /opt/yarn-v$YARN_VERSION/bin/yarn /usr/local/bin/yarn \
    && ln -s /opt/yarn-v$YARN_VERSION/bin/yarnpkg /usr/local/bin/yarnpkg \
    && rm -rf "$GNUPGHOME" yarn-v$YARN_VERSION.tar.gz.asc yarn-v$YARN_VERSION.tar.gz \
    && apk del .build-deps-yarn

# Add docker-entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["node"]

# Copy additional files
COPY / /
RUN rm -rf /tmp/v8-compile-cache*

WORKDIR /home/node
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
COPY n8n-task-runners.json /etc/n8n-task-runners.json
RUN if [[ "$TARGETPLATFORM" = "linux/amd64" ]]; then \
        curl -L -o /usr/local/bin/task-runner-launcher https://github.com/n8n-io/task-runner-launcher/releases/download/v${LAUNCHER_VERSION}/task-runner-launcher_linux_amd64 && \
        chmod +x /usr/local/bin/task-runner-launcher; \
    fi

# Final setup
COPY docker-entrypoint.sh /
RUN mkdir .n8n && chown node:node .n8n
ENV SHELL=/bin/sh
USER node
ENTRYPOINT ["tini", "--", "/docker-entrypoint.sh"]

# Install Python dependencies and MPC tools
USER root
RUN apk add --update --no-cache python3 py3-pip gcc python3-dev musl-dev curl ffmpeg
RUN apk add --no-cache py3-numpy py3-pillow
RUN python3 -m venv /opt/venv
ENV PATH=/opt/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN /opt/venv/bin/pip install --no-cache-dir moviepy

# Create scripts directory
RUN mkdir -p /usr/local/scripts

# Set proper permissions
RUN chown -R node:node /opt/venv

# Install MCP (Model Context Protocol) dependencies
RUN apk add --no-cache \
    git \
    build-base

# Install Node.js dependencies for MCP servers
RUN npm install -g @modelcontextprotocol/sdk

# Install Python MCP SDK
RUN /opt/venv/bin/pip install --no-cache-dir mcp

# Create directory for MCP servers
RUN mkdir -p /opt/mcp-servers && \
    chown -R node:node /opt/mcp-servers

# Install example MCP servers
RUN cd /opt/mcp-servers && \
    git clone https://github.com/modelcontextprotocol/servers.git && \
    chown -R node:node /opt/mcp-servers

# Add MCP server examples to PATH
ENV PATH=/opt/mcp-servers/servers/bin:$PATH
ENV MCP_SERVERS_PATH=/opt/mcp-servers/servers

USER node