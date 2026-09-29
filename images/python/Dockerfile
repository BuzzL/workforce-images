# syntax=docker/dockerfile:1
# Python developer image: the base image plus uv, a uv-managed CPython and ruff.
# pytest is deliberately not global: it belongs in each project's dev
# dependencies (`uv add --dev pytest`), where it can import the project.
ARG BASE_IMAGE=workforce-images/base:local
FROM ${BASE_IMAGE}

ARG TARGETARCH

ARG UV_VERSION=0.12.20
ARG UV_SHA256_AMD64=6590717592ace991ff83a63fef799e3ad9d33ecc8f96c5d6bdd732496e79337f
ARG UV_SHA256_ARM64=8a7aad7bc76a2fae5151566ff3e43eacce0b2a113d5e4de3e4afe3e58fa2441e

# Downloaded by uv and verified against the SHA256 embedded in the pinned uv.
ARG PYTHON_VERSION=3.14.7

ARG RUFF_VERSION=0.16.9

LABEL org.opencontainers.image.description="AI Workforce Python developer image"

USER 0
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /tmp/install

# uv
RUN case "${TARGETARCH}" in \
        amd64) arch=x86_64; sha="${UV_SHA256_AMD64}" ;; \
        arm64) arch=aarch64; sha="${UV_SHA256_ARM64}" ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && dir="uv-${arch}-unknown-linux-gnu" \
    && curl -fsSLO "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${dir}.tar.gz" \
    && echo "${sha}  ${dir}.tar.gz" | sha256sum -c - \
    && tar -xzf "${dir}.tar.gz" --strip-components=1 --no-same-owner -C /usr/local/bin "${dir}/uv" "${dir}/uvx" \
    && rm "${dir}.tar.gz"

# CPython and ruff, installed system-wide (root-owned, read-only for dev).
# The python/python3/python3.X links in /usr/local/bin take precedence over
# Ubuntu's /usr/bin/python3, which stays in place for system tools.
RUN export UV_PYTHON_INSTALL_DIR=/opt/uv/python UV_TOOL_DIR=/opt/uv/tools \
        UV_TOOL_BIN_DIR=/usr/local/bin UV_CACHE_DIR=/tmp/uv-cache \
    && uv python install "${PYTHON_VERSION}" \
    && py="$(uv python find --managed-python "${PYTHON_VERSION}")" \
    && for name in "python${PYTHON_VERSION%.*}" python3 python; do \
        ln -s "${py}" "/usr/local/bin/${name}"; \
    done \
    && uv tool install --python "${PYTHON_VERSION}" "ruff==${RUFF_VERSION}" \
    && rm -rf /tmp/uv-cache /tmp/install

# Back to dev (UID:GID from the base image).
USER 1000:1000
WORKDIR /home/dev
