#!/usr/bin/env bash
# Publish the demo hello-agent bundle (manifest + greeter-skill SKILL.md) to the Control
# Plane, so the runtime's default GARGANTUA_BUNDLE_URL has something real to fetch on a
# fresh checkout — without having to create an agent in the Studio first.
#
# Mirrors the manual smoke.sh pattern (run it from the host after `docker compose up`);
# it is NOT an automatic compose service, because a bind-mounted example dir arrives empty
# when the Docker daemon is remote (Cave). Run it from the shell that has these files.
#
# Usage:  ./seed/seed-hello-agent.sh
set -euo pipefail

CP="${CONTROL_PLANE_URL:-http://localhost:18080}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$HERE/examples/hello-agent/manifest.yaml"
SKILL="$HERE/examples/hello-agent/skills/greeter-skill/SKILL.md"

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; exit 1; }

[ -f "$MANIFEST" ] || fail "manifest not found: $MANIFEST"
[ -f "$SKILL" ] || fail "skill not found: $SKILL"

# Build {manifest, skillFiles:{greeter-skill: <md>}} as JSON (python handles escaping).
BODY=$(MANIFEST="$MANIFEST" SKILL="$SKILL" python3 - <<'PY'
import json, os
manifest = open(os.environ["MANIFEST"], encoding="utf-8").read()
skill = open(os.environ["SKILL"], encoding="utf-8").read()
print(json.dumps({"manifest": manifest, "skillFiles": {"greeter-skill": skill}}))
PY
)

CODE=$(curl -s -o /tmp/gargantua-seed.json -w '%{http_code}' \
  -X POST "$CP/api/v1/registry/bundles" \
  -H 'Content-Type: application/json' -d "$BODY")

case "$CODE" in
  201) pass "published hello-agent@1.0.0 to the Control Plane" ;;
  409) pass "hello-agent@1.0.0 already published (idempotent re-run)" ;;
  *)   fail "publish failed (HTTP $CODE): $(cat /tmp/gargantua-seed.json)" ;;
esac

# Prove the runnable bundle zip is retrievable (what the runtime downloads).
ZCODE=$(curl -s -o /dev/null -w '%{http_code}' \
  "$CP/api/v1/registry/bundles/hello-agent/1.0.0/bundle")
[ "$ZCODE" = "200" ] && pass "bundle zip downloadable at /bundles/hello-agent/1.0.0/bundle" \
  || fail "bundle zip not retrievable (HTTP $ZCODE)"

printf '\n\033[32m✔ seeded — start the runtime with: docker compose --profile agent-runtime up -d --build\033[0m\n'
