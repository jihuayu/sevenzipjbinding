#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'EOF'
scripts/release/maven-release-all.sh is deprecated.

Use the Maven Central Publisher Portal release flow:

  scripts/release/make-central-bundle.sh <version> <distribution-dir>
  scripts/release/publish-central.sh <bundle-zip>
EOF

exit 1
