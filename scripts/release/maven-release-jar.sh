#!/usr/bin/env bash
set -euo pipefail

cat >&2 <<'EOF'
scripts/release/maven-release-jar.sh is deprecated.

OSSRH/Nexus publishing is no longer supported for this fork. Build a Central
Publisher Portal bundle with:

  scripts/release/make-central-bundle.sh <version> <distribution-dir>

Then upload it with:

  scripts/release/publish-central.sh <bundle-zip>
EOF

exit 1
