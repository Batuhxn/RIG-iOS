#!/usr/bin/env bash
# Fetch the pinned Auto Metadata garment encoder into Resources/Models.
#
# The model never enters git. MODEL_LOCK.json pins its SHA-256 and, once the
# versioned GitHub Release asset exists, its URL. A mismatch fails the build.
# With no URL pinned yet, an already-present matching file is accepted and an
# absent one leaves the app to build with Auto Metadata off.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
lock="$root/Resources/Models/MODEL_LOCK.json"
read -r file sha url < <(python3 -c 'import json,sys; l=json.load(open(sys.argv[1])); print(l["file"], l["sha256"], l.get("url") or "-")' "$lock")
target="$root/Resources/Models/$file"

verify() { [ "$(shasum -a 256 "$1" | cut -d" " -f1)" = "$sha" ]; }

if [ -f "$target" ]; then
  if verify "$target"; then echo "model: $file matches pinned SHA-256"; exit 0; fi
  echo "model: $file does not match MODEL_LOCK.json" >&2; exit 1
fi
if [ "$url" = "-" ]; then
  echo "model: no URL pinned yet; building without Auto Metadata classification"; exit 0
fi
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
curl --fail --location --silent --show-error --output "$tmp" "$url"
if ! verify "$tmp"; then echo "model: downloaded bytes do not match pinned SHA-256" >&2; exit 1; fi
mv "$tmp" "$target"; trap - EXIT
echo "model: fetched $file"
