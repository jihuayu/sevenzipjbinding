#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${1:-$HOME/.local/jdks}"
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  arm64) ZULU_ARCH="aarch64" ;;
  x86_64) ZULU_ARCH="x64" ;;
  *)
    echo "Unsupported macOS architecture for zulu@8: $HOST_ARCH" >&2
    exit 1
    ;;
esac
VERSION_DIR="zulu8.94.0.17-ca-jdk8.0.492-macosx_$ZULU_ARCH.jdk"
JDK_DIR="$INSTALL_DIR/$VERSION_DIR"

if [[ -x "$JDK_DIR/Contents/Home/bin/java" ]]; then
  echo "$JDK_DIR/Contents/Home"
  exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to fetch zulu@8 on macOS" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
brew fetch --cask zulu@8 >/dev/null
DMG="$(brew --cache --cask zulu@8)"
MOUNT_POINT=""
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/zulu8-pkg.XXXXXX")"

cleanup() {
  if [[ "$MOUNT_POINT" != "" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

attach_output="$(hdiutil attach -nobrowse -readonly "$DMG")"
MOUNT_POINT="$(printf '%s\n' "$attach_output" | awk -F '\t' '/\\/Volumes\\// {print $NF; exit}')"
if [[ "$MOUNT_POINT" == "" ]]; then
  echo "Could not determine zulu@8 DMG mount point" >&2
  printf '%s\n' "$attach_output" >&2
  exit 1
fi

PKG="$(find "$MOUNT_POINT" -maxdepth 1 -name '*.pkg' -print | head -1)"
if [[ "$PKG" == "" ]]; then
  echo "Could not find zulu@8 pkg in $MOUNT_POINT" >&2
  exit 1
fi

pkgutil --expand "$PKG" "$WORK_DIR/pkg"
mkdir -p "$WORK_DIR/root"
(cd "$WORK_DIR/root" && gzip -dc "$WORK_DIR/pkg/zulu-8.pkg/Payload" | cpio -idm --quiet)

rm -rf "$JDK_DIR"
mv "$WORK_DIR/root" "$JDK_DIR"

"$JDK_DIR/Contents/Home/bin/java" -version >&2
echo "$JDK_DIR/Contents/Home"
