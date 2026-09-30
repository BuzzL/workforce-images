#!/usr/bin/env bash
# Usage: smoke.sh <image> <dockerfile>...
# Runs each Dockerfile's smoke test inside <image>, with the expected versions
# taken from that Dockerfile's *_VERSION ARGs. Run from the repository root.
set -euo pipefail

image=$1; shift
env=() mounts=() cmds=()
for dockerfile in "$@"; do
  dir=$(dirname "$dockerfile")
  name=$(basename "$dir")
  mapfile -t -O "${#env[@]}" env < <(sed -nE 's/^ARG ([A-Z_]+_VERSION)=(.+)$/--env=\1=\2/p' "$dockerfile")
  mounts+=(-v "$PWD/$dir/smoke.sh:/smoke/$name.sh:ro")
  cmds+=("bash /smoke/$name.sh")
done
joined=$(printf '%s && ' "${cmds[@]}")
docker run --rm "${env[@]}" "${mounts[@]}" "$image" bash -c "${joined% && }"
