#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "" || "${2:-}" == "" ]]; then
  echo "Usage: $0 <sevenzipjbinding.jar> <platform.jar>" >&2
  exit 1
fi

CORE_JAR="$1"
PLATFORM_JAR="$2"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sevenzipjbinding-smoke.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/SevenZipSmoke.java" <<'EOF'
import net.sf.sevenzipjbinding.SevenZip;

public class SevenZipSmoke {
    public static void main(String[] args) throws Exception {
        SevenZip.initSevenZipFromPlatformJAR();
        System.out.println("version=" + SevenZip.getSevenZipJBindingVersion());
        System.out.println("platform=" + SevenZip.getUsedPlatform());
    }
}
EOF

javac -classpath "$CORE_JAR:$PLATFORM_JAR" -d "$TMP_DIR" "$TMP_DIR/SevenZipSmoke.java"
java -classpath "$TMP_DIR:$CORE_JAR:$PLATFORM_JAR" SevenZipSmoke
