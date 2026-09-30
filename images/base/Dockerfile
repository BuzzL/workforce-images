# Base developer image for AI Workforce agents (ECS) and human devcontainers.
# Every downloaded tool is pinned by version AND by per-arch SHA256 below, so
# this reviewed file (not the download server) is the trust anchor.
FROM ubuntu:resolute-20260912@sha256:da6fc2be547864451aa253836dd926da33623312df4a9a243e35dc877c378a78

ARG TARGETARCH

ARG NODE_VERSION=24.21.0
ARG NODE_SHA256_AMD64=fd8e59d5a511510f6a298afb548f18c7d2b1be404d8b4a27d94fbe49f56cb2d6
ARG NODE_SHA256_ARM64=6ad1325edbdb5649c379b75a237147a666c95d4f9ae8d340fef2d1575d289ad2

ARG GH_VERSION=2.101.0
ARG GH_SHA256_AMD64=9bca2d1c16825f109907a23307628a2f0698fbf99662b73a5cf0b020293072b8
ARG GH_SHA256_ARM64=b57e8063f18862647c9d22727c32e9da1b963f8bf9db648fe123a6975695640f

ARG TERRAFORM_VERSION=1.16.4
ARG TERRAFORM_SHA256_AMD64=dc94af0eef1147718ad7c8daea792ed199e3e0492eec180d0adafa2a65a879df
ARG TERRAFORM_SHA256_ARM64=8263f301cb1a24489a4adeed147bf28504053f77237b3ea97a0ef2972659de30

ARG AWSCLI_VERSION=2.37.5
ARG AWSCLI_SHA256_AMD64=850ba65f1342a1f725f4868de3c4621ea729af31dac96e54b574cbb0ef309029
ARG AWSCLI_SHA256_ARM64=95d2bac9242185ae3a2970ec38c8766d3bf7b31609a0302dec3643522a676d32

ARG CLAUDE_CODE_VERSION=2.1.284
ARG PRE_COMMIT_VERSION=4.6.2

ARG DEV_USER=dev
ARG DEV_UID=1000
ARG DEV_GID=1000

LABEL org.opencontainers.image.source="https://github.com/BuzzL/workforce-images" \
      org.opencontainers.image.description="AI Workforce base developer image" \
      org.opencontainers.image.licenses="Apache-2.0"

ENV LANG=C.UTF-8

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        jq \
        less \
        make \
        openssh-client \
        python3 \
        python3-venv \
        tini \
        unzip \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/install

# Node.js (LTS)
RUN case "${TARGETARCH}" in \
        amd64) arch=x64; sha="${NODE_SHA256_AMD64}" ;; \
        arm64) arch=arm64; sha="${NODE_SHA256_ARM64}" ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && file="node-v${NODE_VERSION}-linux-${arch}.tar.xz" \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${file}" \
    && echo "${sha}  ${file}" | sha256sum -c - \
    && tar -xJf "${file}" -C /usr/local --strip-components=1 --no-same-owner \
    && rm "${file}"

# GitHub CLI
RUN case "${TARGETARCH}" in \
        amd64) sha="${GH_SHA256_AMD64}" ;; \
        arm64) sha="${GH_SHA256_ARM64}" ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && file="gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" \
    && curl -fsSLO "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${file}" \
    && echo "${sha}  ${file}" | sha256sum -c - \
    && tar -xzf "${file}" --strip-components=2 --no-same-owner -C /usr/local/bin "gh_${GH_VERSION}_linux_${TARGETARCH}/bin/gh" \
    && rm "${file}"

# Terraform
RUN case "${TARGETARCH}" in \
        amd64) sha="${TERRAFORM_SHA256_AMD64}" ;; \
        arm64) sha="${TERRAFORM_SHA256_ARM64}" ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && file="terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" \
    && curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${file}" \
    && echo "${sha}  ${file}" | sha256sum -c - \
    && unzip -q "${file}" terraform -d /usr/local/bin \
    && rm "${file}"

# AWS CLI v2
RUN case "${TARGETARCH}" in \
        amd64) arch=x86_64; sha="${AWSCLI_SHA256_AMD64}" ;; \
        arm64) arch=aarch64; sha="${AWSCLI_SHA256_ARM64}" ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}-${AWSCLI_VERSION}.zip" -o awscliv2.zip \
    && echo "${sha}  awscliv2.zip" | sha256sum -c - \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# pre-commit, in its own virtualenv, with its whole dependency set pinned by
# hash in requirements/pre-commit.txt (wheels only, no dependency resolution).
COPY requirements/pre-commit.txt /tmp/install/pre-commit.txt
RUN awk -v want="pre-commit==${PRE_COMMIT_VERSION}" '$1 == want { found = 1 } END { exit !found }' \
        /tmp/install/pre-commit.txt \
        || { echo "PRE_COMMIT_VERSION=${PRE_COMMIT_VERSION} does not match requirements/pre-commit.txt" >&2; exit 1; } \
    && python3 -c 'import sys; sys.exit(sys.version_info[:2] != (3, 14))' \
        || { echo "requirements/pre-commit.txt targets CPython 3.14; re-resolve it for $(python3 --version)" >&2; exit 1; } \
    && python3 -m venv /opt/pre-commit \
    && /opt/pre-commit/bin/pip install --no-cache-dir --require-hashes --no-deps --only-binary :all: \
        -r /tmp/install/pre-commit.txt \
    && /opt/pre-commit/bin/pip check \
    && ln -s /opt/pre-commit/bin/pre-commit /usr/local/bin/pre-commit

# Claude Code. Updates come from rebuilding this image only: DISABLE_UPDATES
# blocks manual `claude update`/`install`, DISABLE_AUTOUPDATER background ones.
# The root-owned managed settings win over any environment override.
ENV DISABLE_AUTOUPDATER=1 \
    DISABLE_UPDATES=1
RUN npm install --global --allow-scripts=@anthropic-ai/claude-code \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && npm cache clean --force \
    && mkdir -p /etc/claude-code \
    && echo '{"env":{"DISABLE_AUTOUPDATER":"1","DISABLE_UPDATES":"1"}}' > /etc/claude-code/managed-settings.json

# Unprivileged user (no sudo). Ubuntu ships a default "ubuntu" user on UID 1000.
WORKDIR /
RUN if id ubuntu >/dev/null 2>&1; then userdel --remove ubuntu; fi \
    && groupadd --gid "${DEV_GID}" "${DEV_USER}" \
    && useradd --create-home --shell /bin/bash --uid "${DEV_UID}" --gid "${DEV_GID}" "${DEV_USER}" \
    && echo "prefix=/home/${DEV_USER}/.npm-global" > "/home/${DEV_USER}/.npmrc" \
    && chown "${DEV_USER}:${DEV_USER}" "/home/${DEV_USER}/.npmrc" \
    && rm -rf /tmp/install /root/.npm

USER ${DEV_USER}
# User-installed global npm packages come AFTER system tools on PATH, so they
# can never shadow git, gh, aws, node or claude.
ENV PATH=${PATH}:/home/${DEV_USER}/.npm-global/bin
WORKDIR /home/${DEV_USER}

# tini as PID 1: reaps the many child processes agents spawn, and (-g) forwards
# SIGTERM to the whole process group so an ECS task stop shuts down cleanly
# even when the command is a shell wrapping the agent.
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["bash"]
