#!/usr/bin/env bash
# Point the Spin templates and examples at a published release: rewrite the component
# `source` URL and its sha256 digest in every templates/**/{spin.toml,component.txt} and
# examples/*/spin.toml.
#
#   scripts/update-template-refs.sh <version> [owner/repo]
#   scripts/update-template-refs.sh v0.1.0
#   scripts/update-template-refs.sh v0.1.0 myorg/spin-code-sandbox
#
# Downloads each released *.wasm, computes its digest, and updates the templates in place.
# Review with `git diff templates/ examples/` afterwards.
set -euo pipefail

VERSION="${1:?usage: $0 <version> [owner/repo]}"
REPO="${2:-spinframework/spin-code-sandbox}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

for comp in ts-sandbox py-sandbox bundler; do
  url="https://github.com/$REPO/releases/download/$VERSION/$comp.wasm"
  echo ">> $comp -> $url"
  tmp="$(mktemp)"
  curl -fsSL "$url" -o "$tmp"
  digest="sha256:$(sha256 "$tmp")"
  rm -f "$tmp"
  echo "   $digest"

  # Rewrite `... url = "<any-version-of-this-wasm>", digest = "sha256:<64hex>" ...`.
  # perl's s/// exits 0 whether or not it matched, so count the files that end up pinned to
  # this url and digest, and fail if none do (e.g. the source-line format drifted). Counting
  # results rather than changes keeps a re-run for the same release from failing.
  pinned=0
  while IFS= read -r f; do
    comp="$comp" url="$url" digest="$digest" perl -i -pe '
      my ($c, $u, $d) = ($ENV{comp}, $ENV{url}, $ENV{digest});
      s{https://github\.com/[^"]*/\Q$c\E\.wasm", digest = "sha256:[0-9a-f]{64}"}{$u", digest = "$d"}g;
    ' "$f"
    grep -qF "$url\", digest = \"$digest\"" "$f" && pinned=$((pinned + 1))
  done < <(grep -rl --include=spin.toml --include=component.txt --exclude-dir=node_modules \
    "/$comp.wasm" "$ROOT/templates" "$ROOT/examples")
  echo "   pinned in $pinned file(s)"
  if [ "$pinned" -eq 0 ]; then
    echo "   ERROR: no template or example pinned for $comp; the source/digest line format may have changed" >&2
    exit 1
  fi
done

echo ">> done, review: git diff templates/ examples/"
