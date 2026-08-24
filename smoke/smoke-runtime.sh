#!/usr/bin/env bash
# End-to-end smoke test for the RUN loop (the `agent-runtime` profile). Proves the full
# create→launch→test path across all three components:
#   1. Publish a one-skill agent (manifest + real SKILL.md content) to the Control Plane
#   2. The runnable bundle zip is downloadable from the Registry
#   3. A running Runtime answers POST /api/agent/chat with a real LLM reply
#   4. The Runtime exposes the per-turn execution trace at GET /api/traces
#
# Prereqs: core stack up, hello-agent seeded, and the runtime up:
#   docker compose up -d --build --wait
#   ./seed/seed-hello-agent.sh
#   docker compose --profile agent-runtime up -d --build
# Then:  ./smoke/smoke-runtime.sh
set -euo pipefail

CP="${CONTROL_PLANE_URL:-http://localhost:18080}"
RT="${RUNTIME_URL:-http://localhost:18100}"

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; exit 1; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }

step "1. Bundle published + downloadable from the Registry"
curl -fsS "$CP/api/v1/registry/bundles/hello-agent/1.0.0" | grep -q 'hello-agent' \
  && pass "hello-agent@1.0.0 in the Registry" || fail "not published — run ./seed/seed-hello-agent.sh first"
curl -fsS -o /dev/null "$CP/api/v1/registry/bundles/hello-agent/1.0.0/bundle" \
  && pass "runnable bundle zip downloadable" || fail "bundle zip not retrievable"

step "2. Runtime is up and serving the agent"
curl -fsS "$RT/actuator/health/readiness" | grep -q 'UP' \
  && pass "runtime readiness UP" || fail "runtime not ready ($RT)"

step "3. Chat returns a real LLM reply"
RESP=$(curl -fsS -X POST "$RT/api/agent/chat" \
  -H 'Content-Type: application/json' -H 'X-User-Id: smoke' -H 'X-Session-Id: s1' \
  -d '{"message":"Hi, who are you?"}')
echo "$RESP" | grep -q '"text"' && pass "chat responded" || fail "no chat response: $RESP"
echo "$RESP" | grep -q '"skillUsed":"greeter-skill"' \
  && pass "routed to greeter-skill" || fail "unexpected skill: $RESP"

step "4. Execution trace exposed"
curl -fsS "$RT/api/traces" | grep -q 'traceId' \
  && pass "trace timeline available at /api/traces" || fail "no traces"

printf '\n\033[32m✔ run loop OK — create → publish → launch → chat → trace all work\033[0m\n'
