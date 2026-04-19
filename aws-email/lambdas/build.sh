#!/usr/bin/env bash
# Bundles each Lambda handler into a self-contained zip ready for Terraform.
# Usage: ./build.sh
# Output: dist/<handler>.zip

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

DIST="$HERE/dist"
BUILD="$HERE/.build"

HANDLERS=(
  "subscribe"
  "confirm"
  "unsubscribe"
  "bounce-complaint-handler"
  "send-campaign"
  "admin-read"
)

# Ensure dependencies are installed (esbuild + aws-sdk types/runtime during bundling).
if [[ ! -d "$HERE/node_modules" ]]; then
  echo ">> installing npm dependencies"
  npm install --silent --no-audit --no-fund
fi

ESBUILD="$HERE/node_modules/.bin/esbuild"
if [[ ! -x "$ESBUILD" ]]; then
  echo "error: esbuild not found at $ESBUILD" >&2
  exit 1
fi

rm -rf "$DIST" "$BUILD"
mkdir -p "$DIST" "$BUILD"

for name in "${HANDLERS[@]}"; do
  echo ">> bundling $name"
  out_dir="$BUILD/$name"
  mkdir -p "$out_dir"

  "$ESBUILD" "$HERE/${name}.mjs" \
    --bundle \
    --platform=node \
    --target=node20 \
    --format=esm \
    --minify \
    --legal-comments=none \
    --external:@aws-sdk/* \
    --outfile="$out_dir/${name}.mjs"

  # Lambda requires a package.json with "type": "module" to load .mjs via ESM.
  cat > "$out_dir/package.json" <<'EOF'
{ "type": "module" }
EOF

  (cd "$out_dir" && zip -qr "$DIST/${name}.zip" .)
  echo "   -> $DIST/${name}.zip"
done

echo ">> done"
ls -lh "$DIST"
