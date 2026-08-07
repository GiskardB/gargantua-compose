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

## Prerequisites

- Docker + Docker Compose v2 (`docker compose`).
- The sibling source repos checked out **next to this one**, because the JVM/SPA images
  build from source:

  ```
  workspace/
    gargantua-compose/          ← you are here
    gargantua-control-plane/
    gargantua-studio-backend/
    gargantua-studio/
  ```

  `agent-core` resolves from Maven Central, so you do **not** need the `gargantua`
  Runtime repo checked out to build these services.

## Run it

```bash
cp .env.example .env            # optional — defaults work as-is
docker compose up -d --build --wait   # --wait blocks until healthchecks pass
```

Then open the Studio:

- **Studio UI**      → http://localhost:8081   (or `http://<CAVE_HOST>:8081`)
- Studio backend     → http://localhost:8090/actuator/health
- Control Plane      → http://localhost:8080/actuator/health
- MinIO console      → http://localhost:9001   (minioadmin / minioadmin)

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
docker compose down          # keep data
docker compose down -v       # also drop Postgres + MinIO volumes
```

## Notes

- **Ports** are overridable via `.env` (`CONTROL_PLANE_PORT`, `STUDIO_BACKEND_PORT`,
  `STUDIO_PORT`, `MINIO_*_PORT`). Postgres is intentionally **not** published, to avoid
  clashing with a host Postgres.
- **State** lives in the `pgdata` and `miniodata` named volumes. The Control Plane's
  `S3BlobStore` creates the bucket on first publish; the JDBC schema is applied on boot.
- **Profiles**: control-plane runs `postgres,minio`; studio-backend runs `postgres`.
  Both fall back to embedded H2 + filesystem blobs when run outside this compose.
