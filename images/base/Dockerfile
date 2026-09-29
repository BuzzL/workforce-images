# syntax=docker/dockerfile:1
# Base developer image for AI Workforce agents (ECS) and human devcontainers.
# Every tool version is pinned with an ARG; downloads are checksum-verified
# where the vendor publishes checksums.
FROM ubuntu:resolute-20260912

ARG TARGETARCH
ARG NODE_VERSION=24.21.0
ARG GH_VERSION=2.101.0
ARG TERRAFORM_VERSION=1.16.4
ARG AWSCLI_VERSION=2.37.5
ARG CLAUDE_CODE_VERSION=2.1.284
ARG PRE_COMMIT_VERSION=4.6.2
ARG USERNAME=dev
ARG USER_UID=1000

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
        unzip \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/install

# Node.js (LTS)
RUN case "${TARGETARCH}" in amd64) arch=x64 ;; arm64) arch=arm64 ;; *) exit 1 ;; esac \
    && file="node-v${NODE_VERSION}-linux-${arch}.tar.xz" \
    && curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${file}" \
    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | grep " ${file}\$" | sha256sum -c - \
    && tar -xJf "${file}" -C /usr/local --strip-components=1 --no-same-owner \
    && rm "${file}"

# GitHub CLI
RUN file="gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" \
    && curl -fsSLO "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${file}" \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_checksums.txt" | grep " ${file}\$" | sha256sum -c - \
    && tar -xzf "${file}" --strip-components=2 -C /usr/local/bin "gh_${GH_VERSION}_linux_${TARGETARCH}/bin/gh" \
    && rm "${file}"

# Terraform
RUN file="terraform_${TERRAFORM_VERSION}_linux_${TARGETARCH}.zip" \
    && curl -fsSLO "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/${file}" \
    && curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep " ${file}\$" | sha256sum -c - \
    && unzip -q "${file}" terraform -d /usr/local/bin \
    && rm "${file}"

# AWS CLI v2
RUN case "${TARGETARCH}" in amd64) arch=x86_64 ;; arm64) arch=aarch64 ;; *) exit 1 ;; esac \
    && curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${arch}-${AWSCLI_VERSION}.zip" -o awscliv2.zip \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# pre-commit, in its own virtualenv
RUN python3 -m venv /opt/pre-commit \
    && /opt/pre-commit/bin/pip install --no-cache-dir "pre-commit==${PRE_COMMIT_VERSION}" \
    && ln -s /opt/pre-commit/bin/pre-commit /usr/local/bin/pre-commit

# Claude Code. Updates come from rebuilding this image, not from self-update.
ENV DISABLE_AUTOUPDATER=1
RUN npm install --global "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && npm cache clean --force

# Unprivileged user (no sudo). Ubuntu ships a default "ubuntu" user on UID 1000.
RUN userdel --remove ubuntu 2>/dev/null || true \
    && useradd --create-home --shell /bin/bash --uid "${USER_UID}" "${USERNAME}"

USER ${USERNAME}
ENV NPM_CONFIG_PREFIX=/home/${USERNAME}/.npm-global \
    PATH=/home/${USERNAME}/.npm-global/bin:${PATH}
WORKDIR /home/${USERNAME}

CMD ["bash"]
