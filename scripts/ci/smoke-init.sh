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

classpath_entry() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
      else
        printf '%s\n' "$1"
      fi
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) CLASSPATH_SEPARATOR=";" ;;
  *) CLASSPATH_SEPARATOR=":" ;;
esac

CORE_CP="$(classpath_entry "$CORE_JAR")"
PLATFORM_CP="$(classpath_entry "$PLATFORM_JAR")"
TMP_CP="$(classpath_entry "$TMP_DIR")"
COMPILE_CLASSPATH="$CORE_CP$CLASSPATH_SEPARATOR$PLATFORM_CP"
RUN_CLASSPATH="$TMP_CP$CLASSPATH_SEPARATOR$CORE_CP$CLASSPATH_SEPARATOR$PLATFORM_CP"

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

javac -classpath "$COMPILE_CLASSPATH" -d "$TMP_DIR" "$TMP_DIR/SevenZipSmoke.java"
java -classpath "$RUN_CLASSPATH" SevenZipSmoke
