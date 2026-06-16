#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POM_TEMPLATE="$SCRIPT_DIR/maven-pom-template.xml"
GROUP_PATH="com/jihuayu"

usage() {
  cat <<USAGE
Usage: $0 <version> <distribution-dir> [bundle-zip]

Build a Maven Central Publisher Portal bundle from 7-Zip-JBinding CPack
distribution zips.

Environment:
  GPG_PASSPHRASE  Optional passphrase for gpg signing.
  SKIP_GPG=1      Build an unsigned dry-run bundle.
  WORK_DIR=path   Override temporary working directory.
USAGE
}

if [[ "${1:-}" == "" || "${2:-}" == "" ]]; then
  usage
  exit 1
fi

VERSION="$1"
DIST_DIR="$(cd "$2" && pwd)"
BUNDLE_ZIP="${3:-$PWD/sevenzipjbinding-$VERSION-central-bundle.zip}"
WORK_DIR="${WORK_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/sevenzipjbinding-central.XXXXXX")}"
REPO_DIR="$WORK_DIR/repository"
EXTRACT_DIR="$WORK_DIR/extract"
PLACEHOLDER_DIR="$WORK_DIR/placeholder"

cleanup() {
  if [[ "${KEEP_WORK_DIR:-}" != "1" ]]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

require_command jar
require_command unzip
require_command zipinfo
require_command zip
require_command shasum
require_command sed
if [[ "${SKIP_GPG:-}" != "1" ]]; then
  require_command gpg
fi

mkdir -p "$REPO_DIR" "$EXTRACT_DIR" "$PLACEHOLDER_DIR"

artifact_rows=(
  "sevenzipjbinding|AllPlatforms|sevenzipjbinding"
  "sevenzipjbinding-linux-i386|Linux-i386|sevenzipjbinding-Linux-i386"
  "sevenzipjbinding-linux-amd64|Linux-amd64|sevenzipjbinding-Linux-amd64"
  "sevenzipjbinding-linux-arm64|Linux-arm64|sevenzipjbinding-Linux-arm64"
  "sevenzipjbinding-linux-armv5|Linux-armv5|sevenzipjbinding-Linux-armv5"
  "sevenzipjbinding-linux-armv6|Linux-armv6|sevenzipjbinding-Linux-armv6"
  "sevenzipjbinding-linux-armv71|Linux-armv71|sevenzipjbinding-Linux-armv71"
  "sevenzipjbinding-mac-x86_64|Mac-x86_64|sevenzipjbinding-Mac-x86_64"
  "sevenzipjbinding-mac-aarch64|Mac-aarch64|sevenzipjbinding-Mac-aarch64"
  "sevenzipjbinding-windows-x86|Windows-x86|sevenzipjbinding-Windows-x86"
  "sevenzipjbinding-windows-amd64|Windows-amd64|sevenzipjbinding-Windows-amd64"
  "sevenzipjbinding-all-linux|AllLinux|sevenzipjbinding-AllLinux"
  "sevenzipjbinding-all-mac|AllMac|sevenzipjbinding-AllMac"
  "sevenzipjbinding-all-windows|AllWindows|sevenzipjbinding-AllWindows"
  "sevenzipjbinding-all-platforms|AllPlatforms|sevenzipjbinding-AllPlatforms"
)

zip_for_platform() {
  local platform="$1"
  local zip_file="$DIST_DIR/sevenzipjbinding-$VERSION-$platform.zip"
  if [[ ! -f "$zip_file" ]]; then
    echo "Missing distribution zip: $zip_file" >&2
    exit 1
  fi
  printf '%s\n' "$zip_file"
}

zip_entry() {
  local zip_file="$1"
  local suffix="$2"
  local entry
  entry="$(zipinfo -1 "$zip_file" | grep "$suffix\$" | head -1 || true)"
  if [[ "$entry" == "" ]]; then
    echo "Missing entry '*$suffix' in $zip_file" >&2
    exit 1
  fi
  printf '%s\n' "$entry"
}

extract_entry() {
  local zip_file="$1"
  local suffix="$2"
  local dest="$3"
  local entry
  entry="$(zip_entry "$zip_file" "$suffix")"
  unzip -p "$zip_file" "$entry" > "$dest"
}

write_pom() {
  local artifact_id="$1"
  local pom_file="$2"
  local name_postfix="$3"
  sed \
    -e "s/{{dist-version}}/$VERSION/g" \
    -e "s/{{dist-artifactId-postfix}}/${artifact_id#sevenzipjbinding}/g" \
    -e "s/{{dist-name-postfix}}/$name_postfix/g" \
    "$POM_TEMPLATE" > "$pom_file"
}

make_placeholder_jar() {
  local artifact_id="$1"
  local classifier="$2"
  local dest="$3"
  local dir="$PLACEHOLDER_DIR/$artifact_id-$classifier"
  rm -rf "$dir"
  mkdir -p "$dir/META-INF"
  cat > "$dir/META-INF/README.txt" <<EOF
This $classifier artifact is intentionally minimal.

The Java API sources and Javadoc for this native/platform artifact are provided
by com.jihuayu:sevenzipjbinding:$VERSION.
EOF
  jar cf "$dest" -C "$dir" .
}

sign_file() {
  local file="$1"
  if [[ "${SKIP_GPG:-}" == "1" ]]; then
    return
  fi
  if [[ "${GPG_PASSPHRASE:-}" != "" ]]; then
    gpg --batch --yes --pinentry-mode loopback --passphrase "$GPG_PASSPHRASE" --armor --detach-sign "$file"
  else
    gpg --batch --yes --armor --detach-sign "$file"
  fi
}

write_checksums() {
  local file="$1"
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$file" | awk '{print $1}' > "$file.md5"
  else
    md5 -q "$file" > "$file.md5"
  fi
  shasum -a 1 "$file" | awk '{print $1}' > "$file.sha1"
  shasum -a 256 "$file" | awk '{print $1}' > "$file.sha256"
  shasum -a 512 "$file" | awk '{print $1}' > "$file.sha512"
}

prepare_artifact() {
  local artifact_id="$1"
  local platform="$2"
  local jar_base="$3"
  local zip_file
  local artifact_dir
  local base
  local name_postfix

  zip_file="$(zip_for_platform "$platform")"
  artifact_dir="$REPO_DIR/$GROUP_PATH/$artifact_id/$VERSION"
  base="$artifact_dir/$artifact_id-$VERSION"
  name_postfix="${jar_base#sevenzipjbinding}"

  mkdir -p "$artifact_dir"
  extract_entry "$zip_file" "/lib/$jar_base.jar" "$base.jar"
  write_pom "$artifact_id" "$base.pom" "$name_postfix"

  if [[ "$artifact_id" == "sevenzipjbinding" ]]; then
    extract_entry "$zip_file" "/java-src.zip" "$base-sources.jar"
    extract_entry "$zip_file" "/javadoc.zip" "$base-javadoc.jar"
  else
    make_placeholder_jar "$artifact_id" "sources" "$base-sources.jar"
    make_placeholder_jar "$artifact_id" "javadoc" "$base-javadoc.jar"
  fi

  local file
  for file in "$base.pom" "$base.jar" "$base-sources.jar" "$base-javadoc.jar"; do
    sign_file "$file"
  done
  for file in "$artifact_dir"/*; do
    case "$file" in
      *.md5|*.sha1|*.sha256|*.sha512) ;;
      *) write_checksums "$file" ;;
    esac
  done
}

for row in "${artifact_rows[@]}"; do
  IFS='|' read -r artifact_id platform jar_base <<< "$row"
  prepare_artifact "$artifact_id" "$platform" "$jar_base"
done

if [[ "${SKIP_GPG:-}" != "1" ]]; then
  missing_sig_count="$(find "$REPO_DIR" -type f \( -name '*.pom' -o -name '*.jar' \) ! -name '*.asc' -exec sh -c 'test -f "$1.asc" || echo "$1"' sh {} \; | wc -l | tr -d ' ')"
  if [[ "$missing_sig_count" != "0" ]]; then
    echo "Missing signatures in bundle" >&2
    exit 1
  fi
fi

rm -f "$BUNDLE_ZIP"
(cd "$REPO_DIR" && zip -qr "$BUNDLE_ZIP" .)

echo "Created Central bundle: $BUNDLE_ZIP"
