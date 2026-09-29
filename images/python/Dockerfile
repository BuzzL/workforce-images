# Python developer image: the base image plus uv, a uv-managed CPython and ruff.
# pytest is deliberately not global: it belongs in each project's dev
# dependencies (`uv add --dev pytest`), where it can import the project.
#
# BASE_IMAGE has no default on purpose, so a build without it fails instead of
# resolving a name on Docker Hub. CI passes the freshly built base image.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG TARGETARCH

ARG UV_VERSION=0.12.20
ARG UV_SHA256_AMD64=6590717592ace991ff83a63fef799e3ad9d33ecc8f96c5d6bdd732496e79337f
ARG UV_SHA256_ARM64=8a7aad7bc76a2fae5151566ff3e43eacce0b2a113d5e4de3e4afe3e58fa2441e

ARG RUFF_VERSION=0.16.9
ARG RUFF_SHA256_AMD64=1bfbb819b5d4f9af501748862276b60e412d336034d99387691a4d4bce7a6f13
ARG RUFF_SHA256_ARM64=a13061e8f471b49c9d2aa284c32dd54a0e5534d702d1a44e1d7f4c875569586d

# Not hash-pinned here: uv downloads it and verifies it against the SHA256
# embedded in the pinned uv binary (download-metadata.json of that release).
ARG PYTHON_VERSION=3.14.7

LABEL org.opencontainers.image.description="AI Workforce Python developer image"

USER 0
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
WORKDIR /tmp/install

# uv and ruff: static binaries from their GitHub releases.
RUN case "${TARGETARCH}" in \
        amd64) arch=x86_64; uv_sha="${UV_SHA256_AMD64}"; ruff_sha="${RUFF_SHA256_AMD64}" ;; \
        arm64) arch=aarch64; uv_sha="${UV_SHA256_ARM64}"; ruff_sha="${RUFF_SHA256_ARM64}" ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && uv="uv-${arch}-unknown-linux-gnu" \
    && curl -fsSLO "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/${uv}.tar.gz" \
    && echo "${uv_sha}  ${uv}.tar.gz" | sha256sum -c - \
    && tar -xzf "${uv}.tar.gz" --strip-components=1 --no-same-owner -C /usr/local/bin "${uv}/uv" "${uv}/uvx" \
    && ruff="ruff-${arch}-unknown-linux-gnu" \
    && curl -fsSLO "https://github.com/astral-sh/ruff/releases/download/${RUFF_VERSION}/${ruff}.tar.gz" \
    && echo "${ruff_sha}  ${ruff}.tar.gz" | sha256sum -c - \
    && tar -xzf "${ruff}.tar.gz" --strip-components=1 --no-same-owner -C /usr/local/bin "${ruff}/ruff" \
    && rm "${uv}.tar.gz" "${ruff}.tar.gz"

# CPython, installed system-wide under /opt/uv/python (root-owned, read-only
# for dev). The python/python3/python3.X links in /usr/local/bin take
# precedence over Ubuntu's /usr/bin/python3, which stays for system tools.
RUN UV_PYTHON_INSTALL_DIR=/opt/uv/python UV_CACHE_DIR=/tmp/uv-cache \
        uv python install --no-bin "${PYTHON_VERSION}" \
    && py="$(UV_PYTHON_INSTALL_DIR=/opt/uv/python uv python find --managed-python "${PYTHON_VERSION}")" \
    && for name in "python${PYTHON_VERSION%.*}" python3 python; do \
        ln -s "${py}" "/usr/local/bin/${name}"; \
    done \
    && rm -rf /tmp/uv-cache /tmp/install

# Agents stay on the image's Python: uv may not download another interpreter
# implicitly; an explicit `uv python install` still works (into ~/.local).
ENV UV_PYTHON_DOWNLOADS=manual

# Back to dev (UID:GID 1000:1000, DEV_UID/DEV_GID in the base image; the base
# smoke test fails if they change). Numeric for hadolint DL3066.
USER 1000:1000
# uv tool / pip --user executables. After every system dir, like ~/.npm-global.
ENV PATH=${PATH}:/home/dev/.local/bin
WORKDIR /home/dev
