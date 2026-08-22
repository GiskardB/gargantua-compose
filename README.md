# gargantua-compose

Run the **Gargantua agent-creation flow end to end on a single machine — no Kubernetes.**
This is the "does Studio emit something the rest of the platform accepts?" test, wired
up as a Docker Compose stack.

```
browser ─▶ studio            nginx: serves the SPA, proxies /api same-origin
              └─▶ studio-backend   BFF: builds gargantua.ai/v1 manifests (agent-core)
                     └─▶ control-plane   Registry + Catalog
                            ├─▶ postgres   control-plane + studio state
                            └─▶ minio      bundle manifest blobs
```

> **Scope.** Creating an agent only needs Studio → backend → Control Plane. *Running*
> an agent (the Runtime, with Mongo/Redis) is deliberately out of this slice — it comes
> next. Kubernetes and the Operator stay Phase 5; they are never required to try the
> platform.

> **Status: verified against a live Docker daemon (2026-08)** — all 5 services build and
> report healthy, and `smoke/smoke.sh` passes end to end (build → publish → catalog
> round-trip, confirmed against the real Control Plane response).

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
- Studio backend     → http://localhost:18090/actuator/health
- Control Plane      → http://localhost:18080/actuator/health
- MinIO console      → http://localhost:19001   (minioadmin / minioadmin)

> **Ports are in a high range on purpose** so they never clash with Cave's own services
> (forgejo 3000, postgres 5432, redis 6379, cave-publish 7443, 8080, minio 9000/9001).
> Change any of them in `.env`.
>
> **Published ports bind on the Docker *host***, which is not always `localhost` from
> where you're running commands — e.g. a remote daemon, Docker Desktop's VM, or (in Cave)
> a `DOCKER_HOST=tcp://...` setup where the CLI's shell and the daemon are different
> machines. If `curl localhost:18080` refuses to connect but the containers report
> healthy (`docker compose ps`), try the actual Docker host address instead (in Cave,
> `<CAVE_HOST>`).

The SPA talks to the backend **same-origin** through nginx, so the UI works whether you
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

## Tear down

```bash
docker compose down          # keep data   (Windows: stop.bat)
docker compose down -v       # also drop Postgres + MinIO volumes   (Windows: stop.bat clean)
```

## Notes

- **Ports** default to a high range (`18080` CP, `18090` backend, `18081` Studio,
  `19000/19001` MinIO) to avoid clashing with Cave; all overridable via `.env`
  (`CONTROL_PLANE_PORT`, `STUDIO_BACKEND_PORT`, `STUDIO_PORT`, `MINIO_*_PORT`). Postgres
  is intentionally **not** published, to avoid clashing with a host Postgres.
- **`start.bat` / `stop.bat`** are the Windows convenience wrappers around
  `docker compose up`/`down`; the raw `docker compose` commands work everywhere.
- **State** lives in the `pgdata` and `miniodata` named volumes. The Control Plane's
  `S3BlobStore` creates the bucket on first publish; the JDBC schema is applied on boot.
- **Profiles**: control-plane runs `postgres,minio`; studio-backend runs `postgres`.
  Both fall back to embedded H2 + filesystem blobs when run outside this compose.
