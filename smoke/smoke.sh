#!/usr/bin/env bash
# End-to-end smoke test for the Gargantua vertical slice.
#
# Proves the agent-creation flow works across every hop:
#   1. Control Plane and Studio backend are healthy.
#   2. Studio serves the SPA and the backend API from the same origin.
#   3. The backend BUILDS a gargantua.ai/v1 manifest from a form draft (agent-core).
#   4. The backend PUBLISHES it to the Control Plane Registry.
#   5. The Control Plane CATALOG then exposes the derived capability
#      (the round-trip that answers "does Studio emit something compatible?").
#
# Run it after `docker compose up -d --wait`. No jq required.
set -euo pipefail

# Studio is now one image (SPA + BFF on the same origin), so SB and UI share a port.
CP="${CONTROL_PLANE_URL:-http://localhost:18080}"
UI="${STUDIO_URL:-http://localhost:18081}"
SB="${STUDIO_BACKEND_URL:-$UI}"

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; exit 1; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# A minimal but valid Agent draft (the shape the Studio form POSTs).
read -r -d '' DRAFT <<'JSON' || true
{
  "metadata": {
    "name": "smoke-agent",
    "version": "1.0.0",
    "description": "Vertical-slice smoke test agent",
    "owner": "smoke",
    "labelsText": "env=smoke"
  },
  "runtime": { "image": "ghcr.io/giskardb/gargantua-runtime:1.0", "minVersion": "1.0" },
  "model": { "primary": "gpt-4o", "fallback": "", "routing": "", "temperature": "0.7", "maxTokens": "1000" },
  "capabilities": [
    {
      "name": "smoke-capability",
      "description": "A capability created by the smoke test",
      "version": "1.0.0",
      "implementedBy": "smoke-skill",
      "inputSchema": "",
      "outputSchema": "",
      "tags": "smoke"
    }
  ],
  "mcpServers": [],
  "memoryLayers": ["WORKING"],
  "defaultSkill": "smoke-skill",
  "allowedRolesText": "",
  "guardrails": []
}
JSON

step "1. Health"
curl -fsS "$CP/actuator/health"  | grep -q '"status":"UP"' && pass "control-plane UP"       || fail "control-plane not UP ($CP)"
curl -fsS "$SB/actuator/health"  | grep -q '"status":"UP"' && pass "studio-backend UP"       || fail "studio-backend not UP ($SB)"

step "2. Studio SPA + same-origin API"
curl -fsS "$UI/" | grep -qi '<div id="root"' && pass "SPA served at $UI"                     || fail "SPA not served ($UI)"
# Same origin: the browser reaches the backend on the port that served the SPA.
curl -fsS "$UI/actuator/health" | grep -q '"status":"UP"' && pass "backend reachable on the SPA origin" || fail "backend not reachable on the SPA origin"

step "3. Build manifest (form draft → gargantua.ai/v1 YAML)"
BUILD=$(curl -fsS -X POST "$SB/api/studio/manifest/build" -H 'Content-Type: application/json' -d "$DRAFT")
echo "$BUILD" | grep -q '"valid":true' && pass "manifest valid"                              || fail "build invalid: $BUILD"
echo "$BUILD" | grep -q 'apiVersion: gargantua.ai/v1' && pass "emits gargantua.ai/v1"        || fail "unexpected manifest: $BUILD"

step "4. Publish to Control Plane Registry"
PUB_CODE=$(curl -s -o /tmp/gargantua-pub.json -w '%{http_code}' -X POST "$SB/api/studio/publish" \
  -H 'Content-Type: application/json' -d "$DRAFT")
case "$PUB_CODE" in
  201) pass "published (201 Created)";;
  409) pass "already published (409) — idempotent re-run";;
  *)   fail "publish failed (HTTP $PUB_CODE): $(cat /tmp/gargantua-pub.json)";;
esac

step "5. Catalog round-trip (Control Plane → studio-backend)"
CAPS=$(curl -fsS "$SB/api/studio/capabilities")
echo "$CAPS" | grep -q 'smoke-capability' && pass "capability visible in Catalog via backend" \
  || fail "capability not found in catalog: $CAPS"
# And directly on the Control Plane, to prove it is CP state, not a backend echo.
curl -fsS "$CP/api/v1/catalog/capabilities" | grep -q 'smoke-capability' \
  && pass "capability present in Control Plane Catalog" || fail "not in CP catalog"

printf '\n\033[32m✔ vertical slice OK — Studio output is compatible with the Control Plane\033[0m\n'
