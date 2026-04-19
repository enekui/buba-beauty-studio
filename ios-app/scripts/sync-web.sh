#!/usr/bin/env bash
#
# sync-web.sh
#
# Copia los assets web canonicos (index.html, img/, js/, privacy.html)
# desde la raiz del repo a ios-app/www/, que es lo que Capacitor empaqueta
# en el bundle nativo iOS.
#
# Ejecutar desde ios-app/ con `npm run build:web`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$IOS_APP_DIR/.." && pwd)"
WWW_DIR="$IOS_APP_DIR/www"

echo "[sync-web] Repo root: $REPO_ROOT"
echo "[sync-web] Target:    $WWW_DIR"

rm -rf "$WWW_DIR"
mkdir -p "$WWW_DIR"

cp "$REPO_ROOT/index.html" "$WWW_DIR/index.html"

if [ -f "$REPO_ROOT/privacy.html" ]; then
  cp "$REPO_ROOT/privacy.html" "$WWW_DIR/privacy.html"
fi

rsync -a --delete "$REPO_ROOT/img/" "$WWW_DIR/img/"
rsync -a --delete "$REPO_ROOT/js/"  "$WWW_DIR/js/"

echo "[sync-web] OK - $(find "$WWW_DIR" -type f | wc -l | tr -d ' ') archivos copiados"
