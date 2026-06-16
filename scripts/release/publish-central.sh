#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 <bundle-zip> [deployment-name]

Upload a Maven Central Publisher Portal bundle and wait until validation
finishes. The default publishing type is USER_MANAGED.

Environment:
  CENTRAL_TOKEN_USERNAME  Central Portal user token username.
  CENTRAL_TOKEN_PASSWORD  Central Portal user token password.
  CENTRAL_BASE_URL        Optional, defaults to https://central.sonatype.com
  PUBLISHING_TYPE         Optional, defaults to USER_MANAGED.
  POLL_SECONDS            Optional, defaults to 10.
  POLL_TIMEOUT_SECONDS    Optional, defaults to 1800.
USAGE
}

if [[ "${1:-}" == "" ]]; then
  usage
  exit 1
fi

BUNDLE_ZIP="$1"
DEPLOYMENT_NAME="${2:-$(basename "$BUNDLE_ZIP" .zip)}"
CENTRAL_BASE_URL="${CENTRAL_BASE_URL:-https://central.sonatype.com}"
PUBLISHING_TYPE="${PUBLISHING_TYPE:-USER_MANAGED}"
POLL_SECONDS="${POLL_SECONDS:-10}"
POLL_TIMEOUT_SECONDS="${POLL_TIMEOUT_SECONDS:-1800}"

if [[ ! -f "$BUNDLE_ZIP" ]]; then
  echo "Bundle zip not found: $BUNDLE_ZIP" >&2
  exit 1
fi

if [[ "${CENTRAL_TOKEN_USERNAME:-}" == "" || "${CENTRAL_TOKEN_PASSWORD:-}" == "" ]]; then
  echo "CENTRAL_TOKEN_USERNAME and CENTRAL_TOKEN_PASSWORD are required" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Required command not found: curl" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Required command not found: python3" >&2
  exit 1
fi

AUTH_TOKEN="$(printf '%s:%s' "$CENTRAL_TOKEN_USERNAME" "$CENTRAL_TOKEN_PASSWORD" | base64 | tr -d '\n')"
UPLOAD_URL="$CENTRAL_BASE_URL/api/v1/publisher/upload?name=$DEPLOYMENT_NAME&publishingType=$PUBLISHING_TYPE"

echo "Uploading $BUNDLE_ZIP to Central Portal as '$DEPLOYMENT_NAME' ($PUBLISHING_TYPE)"
upload_response="$(
  curl -fsS \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -F "bundle=@$BUNDLE_ZIP" \
    "$UPLOAD_URL"
)"

deployment_id="$(
  python3 -c 'import json,sys
text=sys.stdin.read().strip()
try:
    data=json.loads(text)
    print(data.get("deploymentId") or data.get("id") or data.get("deployment_id") or "")
except Exception:
    print(text.strip("\""))
' <<< "$upload_response"
)"

if [[ "$deployment_id" == "" ]]; then
  echo "Could not parse deployment id from upload response:" >&2
  echo "$upload_response" >&2
  exit 1
fi

echo "Deployment id: $deployment_id"

deadline=$((SECONDS + POLL_TIMEOUT_SECONDS))
while true; do
  status_response="$(
    curl -fsS \
      -H "Authorization: Bearer $AUTH_TOKEN" \
      "$CENTRAL_BASE_URL/api/v1/publisher/status?id=$deployment_id"
  )"
  state="$(
    python3 -c 'import json,sys
data=json.load(sys.stdin)
print(data.get("deploymentState") or data.get("state") or data.get("status") or "")
' <<< "$status_response"
  )"

  echo "Central Portal state: $state"
  case "$state" in
    VALIDATED|PUBLISHED)
      echo "Deployment is ready: $deployment_id"
      exit 0
      ;;
    FAILED)
      echo "Deployment validation failed:" >&2
      echo "$status_response" >&2
      exit 1
      ;;
  esac

  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for Central validation:" >&2
    echo "$status_response" >&2
    exit 1
  fi
  sleep "$POLL_SECONDS"
done
