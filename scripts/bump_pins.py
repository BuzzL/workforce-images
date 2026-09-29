#!/usr/bin/env python3
"""Find newer versions of the tools pinned with ARGs in images/*/Dockerfile.

For each tool it finds the latest release, skips releases younger than the
cooldown, takes the per-arch SHA256 from the vendor's checksum files (or by
hashing the artifact when the vendor publishes none) and rewrites the ARGs.

  bump_pins.py --list [--min-age-days N]    one "tool version" line per bump
  bump_pins.py --apply TOOL [--min-age-days N]
                                            rewrite the Dockerfile for TOOL

Standard library only. GITHUB_TOKEN, when set, is used for api.github.com.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / "images/base/Dockerfile"
PYTHON = ROOT / "images/python/Dockerfile"
ARCHES = ("amd64", "arm64")

# --------------------------------------------------------------------------
# Pure helpers (unit-tested offline)

ARG_RE = re.compile(r"^ARG (?P<name>[A-Z0-9_]+)=(?P<value>\S+)$", re.MULTILINE)


def read_args(text: str) -> dict[str, str]:
    return {m["name"]: m["value"] for m in ARG_RE.finditer(text)}


def write_args(text: str, updates: dict[str, str]) -> str:
    missing = set(updates) - set(read_args(text))
    if missing:
        raise KeyError(f"ARGs not found: {sorted(missing)}")
    return ARG_RE.sub(
        lambda m: f"ARG {m['name']}={updates.get(m['name'], m['value'])}", text
    )


def version_key(version: str) -> tuple[int, ...]:
    if not re.fullmatch(r"\d+(\.\d+)*", version):
        raise ValueError(f"not a release version: {version!r}")
    return tuple(int(part) for part in version.split("."))


def checksum_for(checksums: str, filename: str) -> str:
    """Return the sha256 for filename from a `<sha>  <file>` checksum list."""
    found = [
        line.split()[0]
        for line in checksums.splitlines()
        if len(line.split()) == 2 and line.split()[1].lstrip("*") == filename
    ]
    if len(found) != 1 or not re.fullmatch(r"[0-9a-f]{64}", found[0]):
        raise ValueError(f"expected exactly one sha256 for {filename}, got {found}")
    return found[0]


def old_enough(published: dt.datetime | None, now: dt.datetime, min_age_days: int) -> bool:
    if published is None:  # age unknown: inherits the cooldown of what pins it
        return True
    return now - published >= dt.timedelta(days=min_age_days)


# --------------------------------------------------------------------------
# Network


def _get(url: str) -> bytes:
    headers = {"User-Agent": "workforce-images-bump-pins"}
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r:
        return r.read()


def get_text(url: str) -> str:
    return _get(url).decode()


def get_json(url: str):
    return json.loads(_get(url))


def sha256_of(url: str) -> str:
    return hashlib.sha256(_get(url)).hexdigest()


def parse_time(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def github_latest(repo: str) -> tuple[str, dt.datetime]:
    release = get_json(f"https://api.github.com/repos/{repo}/releases/latest")
    return release["tag_name"].removeprefix("v"), parse_time(release["published_at"])


# --------------------------------------------------------------------------
# Tools


@dataclass
class Tool:
    name: str
    dockerfile: Path
    version_arg: str
    latest: Callable[[str], tuple[str, dt.datetime | None]]
    hashes: Callable[[str], dict[str, str]] = lambda version: {}
    sha_args: dict[str, str] = field(default_factory=dict)  # arch -> ARG name


def node_latest(current: str) -> tuple[str, dt.datetime]:
    major = current.split(".")[0]
    releases = [
        r for r in get_json("https://nodejs.org/dist/index.json")
        if r["version"].startswith(f"v{major}.") and r["lts"]
    ]
    best = max(releases, key=lambda r: version_key(r["version"][1:]))
    return best["version"][1:], parse_time(best["date"] + "T00:00:00+00:00")


def node_hashes(v: str) -> dict[str, str]:
    sums = get_text(f"https://nodejs.org/dist/v{v}/SHASUMS256.txt")
    return {a: checksum_for(sums, f"node-v{v}-linux-{n}.tar.xz") for a, n in (("amd64", "x64"), ("arm64", "arm64"))}


def gh_hashes(v: str) -> dict[str, str]:
    sums = get_text(f"https://github.com/cli/cli/releases/download/v{v}/gh_{v}_checksums.txt")
    return {a: checksum_for(sums, f"gh_{v}_linux_{a}.tar.gz") for a in ARCHES}


def terraform_hashes(v: str) -> dict[str, str]:
    sums = get_text(f"https://releases.hashicorp.com/terraform/{v}/terraform_{v}_SHA256SUMS")
    return {a: checksum_for(sums, f"terraform_{v}_linux_{a}.zip") for a in ARCHES}


def awscli_latest(current: str) -> tuple[str, dt.datetime]:
    tags = get_json("https://api.github.com/repos/aws/aws-cli/tags?per_page=100")
    best = max(
        (t for t in tags if re.fullmatch(r"2\.\d+\.\d+", t["name"])),
        key=lambda t: version_key(t["name"]),
    )
    commit = get_json(best["commit"]["url"])
    return best["name"], parse_time(commit["commit"]["committer"]["date"])


def awscli_hashes(v: str) -> dict[str, str]:
    # AWS publishes no checksum file: hash the artifacts themselves.
    url = "https://awscli.amazonaws.com/awscli-exe-linux-{}-" + v + ".zip"
    return {"amd64": sha256_of(url.format("x86_64")), "arm64": sha256_of(url.format("aarch64"))}


def npm_latest(package: str) -> Callable[[str], tuple[str, dt.datetime]]:
    def latest(current: str) -> tuple[str, dt.datetime]:
        meta = get_json(f"https://registry.npmjs.org/{package}")
        version = meta["dist-tags"]["latest"]
        return version, parse_time(meta["time"][version])
    return latest


def astral_hashes(project: str) -> Callable[[str], dict[str, str]]:
    def hashes(v: str) -> dict[str, str]:
        out = {}
        for arch, triple in (("amd64", "x86_64"), ("arm64", "aarch64")):
            name = f"{project}-{triple}-unknown-linux-gnu.tar.gz"
            text = get_text(f"https://github.com/astral-sh/{project}/releases/download/{v}/{name}.sha256")
            out[arch] = checksum_for(text, name)
        return out
    return hashes


def cpython_latest(current: str) -> tuple[str, None]:
    """Latest CPython of the same minor that the pinned uv can install."""
    uv_version = read_args(PYTHON.read_text())["UV_VERSION"]
    meta = get_json(
        f"https://raw.githubusercontent.com/astral-sh/uv/{uv_version}/crates/uv-python/download-metadata.json"
    )
    minor = ".".join(current.split(".")[:2])
    versions = {
        f"{v['major']}.{v['minor']}.{v['patch']}"
        for v in meta.values()
        if v.get("name") == "cpython" and f"{v['major']}.{v['minor']}" == minor
        and not v.get("prerelease") and v.get("os") == "linux" and v.get("variant") in (None, "")
    }
    return max(versions, key=version_key), None


TOOLS = [
    Tool("node", BASE, "NODE_VERSION", node_latest, node_hashes,
         {"amd64": "NODE_SHA256_AMD64", "arm64": "NODE_SHA256_ARM64"}),
    Tool("gh", BASE, "GH_VERSION", lambda c: github_latest("cli/cli"), gh_hashes,
         {"amd64": "GH_SHA256_AMD64", "arm64": "GH_SHA256_ARM64"}),
    Tool("terraform", BASE, "TERRAFORM_VERSION", lambda c: github_latest("hashicorp/terraform"),
         terraform_hashes, {"amd64": "TERRAFORM_SHA256_AMD64", "arm64": "TERRAFORM_SHA256_ARM64"}),
    Tool("awscli", BASE, "AWSCLI_VERSION", awscli_latest, awscli_hashes,
         {"amd64": "AWSCLI_SHA256_AMD64", "arm64": "AWSCLI_SHA256_ARM64"}),
    Tool("claude-code", BASE, "CLAUDE_CODE_VERSION", npm_latest("@anthropic-ai/claude-code")),
    Tool("uv", PYTHON, "UV_VERSION", lambda c: github_latest("astral-sh/uv"), astral_hashes("uv"),
         {"amd64": "UV_SHA256_AMD64", "arm64": "UV_SHA256_ARM64"}),
    Tool("ruff", PYTHON, "RUFF_VERSION", lambda c: github_latest("astral-sh/ruff"), astral_hashes("ruff"),
         {"amd64": "RUFF_SHA256_AMD64", "arm64": "RUFF_SHA256_ARM64"}),
    Tool("cpython", PYTHON, "PYTHON_VERSION", cpython_latest),
]
# Not automated: pre-commit (its hash-pinned dependency set in
# images/base/requirements/pre-commit.txt needs re-resolving).


def proposal(tool: Tool, min_age_days: int, now: dt.datetime) -> str | None:
    current = read_args(tool.dockerfile.read_text())[tool.version_arg]
    latest, published = tool.latest(current)
    if version_key(latest) <= version_key(current):
        return None
    if not old_enough(published, now, min_age_days):
        print(f"{tool.name}: {latest} is younger than {min_age_days} days, skipped", file=sys.stderr)
        return None
    return latest


def apply(tool: Tool, version: str) -> None:
    hashes = tool.hashes(version)
    if set(hashes) != set(tool.sha_args):
        raise ValueError(f"{tool.name}: expected hashes for {sorted(tool.sha_args)}, got {sorted(hashes)}")
    updates = {tool.version_arg: version, **{tool.sha_args[a]: h for a, h in hashes.items()}}
    tool.dockerfile.write_text(write_args(tool.dockerfile.read_text(), updates))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--list", action="store_true")
    mode.add_argument("--apply", metavar="TOOL", choices=[t.name for t in TOOLS])
    parser.add_argument("--min-age-days", type=int, default=7)
    args = parser.parse_args()
    now = dt.datetime.now(dt.timezone.utc)

    if args.list:
        for tool in TOOLS:
            version = proposal(tool, args.min_age_days, now)
            if version:
                print(tool.name, version)
        return 0

    tool = next(t for t in TOOLS if t.name == args.apply)
    version = proposal(tool, args.min_age_days, now)
    if not version:
        print(f"{tool.name}: nothing to bump", file=sys.stderr)
        return 1
    apply(tool, version)
    print(tool.name, version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
