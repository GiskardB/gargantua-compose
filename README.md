# gargantua-compose

Run the **Gargantua agent-creation flow end to end on a single machine — no Kubernetes.**
This is the "does Studio emit something the rest of the platform accepts?" test, wired
up as a Docker Compose stack.

```
browser ─▶ studio            ONE image: Spring serves the SPA at / and the BFF API at /api
              └─▶ control-plane   Registry + Catalog
                     └─▶ postgres   control-plane + studio state + bundle blobs
```

> **Scope.** Creating an agent only needs Studio → backend → Control Plane. *Running*
> an agent (the Runtime, with Mongo/Redis) is deliberately out of this slice — it comes
> next. Kubernetes and the Operator stay Phase 5; they are never required to try the
> platform.

> **Status: verified against a live Docker daemon (2026-08)** — all 5 core services build
> and report healthy, and `smoke/smoke.sh` passes end to end (build → publish → catalog
> round-trip, confirmed against the real Control Plane response). The optional
> `agent-runtime` profile is verified too: a bundle boots, its skill registers, and
> `POST /api/agent/chat` returns a real LLM-generated reply (see below).

## Prerequisites

- Docker + Docker Compose v2 (`docker compose`) **with BuildKit**. The JVM images use a
  named build context (`additional_contexts`), which the classic (non-BuildKit) builder
  rejects with `the classic builder doesn't support additional contexts`. If your Docker
  doesn't default to BuildKit, prefix build/up commands with `DOCKER_BUILDKIT=1`.
- The sibling source repos checked out **next to this one**, because the JVM/SPA images
  build from source:

  ```
  workspace/
    gargantua-compose/          ← you are here
    gargantua/                  ← Runtime repo — REQUIRED: agent-core is built from it
    gargantua-control-plane/
    gargantua-studio-backend/
    gargantua-studio/
  ```

  The JVM images build the shared **`agent-core` from source** (via the `runtime_src`
  named build context = `../gargantua`), so **no Maven Central release is needed** — but
  the `gargantua` Runtime repo **must** be checked out as a sibling. This is what lets the
  stack build while the model is on a `-SNAPSHOT`.

## Run it

```bash
cp .env.example .env            # optional — defaults work as-is
DOCKER_BUILDKIT=1 docker compose up -d --build --wait   # --wait blocks until healthchecks pass
```

**Windows:** just double-click **`start.bat`** (creates `.env` if missing, builds and
starts, prints the URLs) and **`stop.bat`** to stop (`stop.bat clean` also wipes the data
volumes).

Then open the Studio:

- **Studio UI**      → http://localhost:18081   (or `http://<CAVE_HOST>:18081`)
- Studio backend     → http://localhost:18081/actuator/health   (same port: one image serves both)
- Control Plane      → http://localhost:18080/actuator/health

> **Ports are in a high range on purpose** so they never clash with Cave's own services
> (forgejo 3000, postgres 5432, redis 6379, cave-publish 7443, 8080).
> Change any of them in `.env`.
>
> **Published ports bind on the Docker *host***, which is not always `localhost` from
> where you're running commands — e.g. a remote daemon, Docker Desktop's VM, or (in Cave)
> a `DOCKER_HOST=tcp://...` setup where the CLI's shell and the daemon are different
> machines. If `curl localhost:18080` refuses to connect but the containers report
> healthy (`docker compose ps`), try the actual Docker host address instead (in Cave,
> `<CAVE_HOST>`).

The SPA and its backend are the **same origin** (one Spring process serves both), so the UI works whether you
reach it on `localhost` or a LAN IP — no rebuild per host, no CORS.

## Verify the flow

```bash
./smoke/smoke.sh
```

It builds a manifest from a form draft, publishes it to the Control Plane Registry, and
confirms the derived capability shows up in the Catalog — through both the backend and
the Control Plane directly. Green means Studio's output is compatible with the platform.

You can also do it by hand in the UI: open the **Agent Designer**, keep the sample agent,
hit **Publish**, then open the **Capability Designer** / **Workload Designer** — they flip
from "sample data" to **live** and list what you just published.

## Actually running an agent (optional) — `agent-runtime` profile

The five services above only cover *creating* an agent. To also *run* one end to end —
with a real LLM but **no external API key** (a local Ollama) — bring up the opt-in profile.
Unlike before, the runtime no longer bakes in a bundle: it **fetches the published bundle
from the Control Plane** at startup (`GARGANTUA_BUNDLE_URL`), so it runs whatever you
publish — from the Studio or the seed script below.

**Path A — the default hello-agent, from the CLI:**

```bash
# 1) core stack up (if not already)
DOCKER_BUILDKIT=1 docker compose up -d --build --wait
# 2) publish the demo bundle to the Control Plane (manifest + greeter-skill SKILL.md)
./seed/seed-hello-agent.sh
# 3) bring up ollama + the runtime (fetches hello-agent@1.0.0 from the Control Plane)
DOCKER_BUILDKIT=1 docker compose --profile agent-runtime up -d --build

curl -X POST http://localhost:18100/api/agent/chat \
  -H 'Content-Type: application/json' -H 'X-User-Id: me' -H 'X-Session-Id: s1' \
  -d '{"message":"Hi, who are you?"}'
# → {"text":"... running on the Gargantua Runtime ...","skillUsed":"greeter-skill",...}
```

The runtime uses the `embedded` Spring profile (in-memory, no Mongo/Redis) and `semantic`
ONNX routing (no LLM call needed just to route). `./smoke/smoke-runtime.sh` checks this
whole loop. First CPU inference takes a few seconds; the tiny default model keeps it snappy.

**Path B — create your own agent in the Studio and launch it:**

1. Bring up the core stack, plus ollama and the runtime image (needed as the launch target):
   ```bash
   DOCKER_BUILDKIT=1 docker compose up -d --build --wait
   DOCKER_BUILDKIT=1 docker compose --profile agent-runtime up -d ollama ollama-pull
   DOCKER_BUILDKIT=1 docker compose --profile agent-runtime build runtime   # tags gargantua-runtime:local
   ```
2. In the Studio (`http://localhost:18081`): design an agent and a skill, then **Publish**.
   For this local demo leave the model **blank** (or set it to your Ollama tag,
   e.g. `qwen2.5:0.5b`) — a pinned cloud model like `gpt-4o` won't exist on Ollama.
3. Click **Launch** on the manifest preview. The Studio backend runs the (editable) launch
   command — a `docker run` of `gargantua-runtime:local` pointed at your published bundle.
4. Test it: the Studio **Playground** (set the Runtime URL to `http://localhost:18100`),
   the runtime's own chat UI at `http://localhost:18100/`, or curl as above. The
   **Trace Explorer** shows the per-turn execution timeline from `/api/traces`.

> **How Launch reaches Docker.** `studio-backend` runs the launch command against the Docker
> daemon via `DOCKER_HOST` (Cave's remote socket-proxy) or a bind-mounted `/var/run/docker.sock`.
> It joins the external `cave` network to reach that proxy. This runs a configured command
> with the backend's privileges — **local-dev/demo only, never expose this backend.** The
> command is fully editable (in the UI or via `GARGANTUA_LAUNCH_COMMAND_TEMPLATE`), so it can
> become `kubectl` or anything else without a code change.
>
> On a **non-Cave** host (standard local Docker), remove the `cave` external network from
> `docker-compose.yml` (and studio-backend's `cave` entry) and leave `DOCKER_HOST` unset so
> the mounted `docker.sock` is used.

## Tear down

```bash
docker compose down          # keep data   (Windows: stop.bat)
docker compose down -v       # also drop Postgres volumes   (Windows: stop.bat clean)
```

## Notes

- **Ports** default to a high range (`18080` CP, `18081` Studio UI + backend)
  to avoid clashing with Cave; all overridable via `.env`
  (`CONTROL_PLANE_PORT`, `STUDIO_PORT`). Postgres
  is intentionally **not** published, to avoid clashing with a host Postgres.
- **Studio's API is reachable only same-origin and from loopback origins.** That is all
  this stack needs. If you front the SPA from another origin, set
  `GARGANTUA_CORS_ALLOWED_ORIGIN_PATTERNS` on the `studio` service.
- **The Control Plane does not launch runtimes here.** Its own launch endpoint is opt-in
  (`gargantua.launch.enabled`) and left off: Studio runs the launch and reports the result.
- **Rebuilding the runtime image reuses a Maven cache** (a BuildKit cache mount in
  `runtime.Dockerfile`), so a source change recompiles without re-downloading dependencies.
- **`start.bat` / `stop.bat`** are the Windows convenience wrappers around
  `docker compose up`/`down`; the raw `docker compose` commands work everywhere.
- **State** lives in the `pgdata` named volume. The Control Plane's
  `PostgresBlobStore` writes manifest + bundle bytes into the `cp_document` table alongside the JSON state.
- **Profiles**: control-plane runs `postgres`; studio-backend runs `postgres`.
  Both fall back to embedded H2 when run outside this compose.
