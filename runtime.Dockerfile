# Gargantua Runtime image — generic, no bundle baked in.
#
# The runtime FETCHES its bundle at startup from the Control Plane via GARGANTUA_BUNDLE_URL
# (an HTTP download), so nothing agent-specific lives in this image. That's what lets one
# image run any published agent, and lets the Studio "Launch" button `docker run` this exact
# image pointed at a freshly published bundle. (Earlier this baked ./examples/hello-agent in
# to work around remote-daemon bind mounts; the HTTP fetch removes that need entirely.)
#
# The Runtime source is supplied as the named context `runtime_src` (= ../gargantua).

# 1) Build the runtime jar from source.
FROM maven:3.9-eclipse-temurin-25-alpine AS builder
WORKDIR /src
COPY --from=runtime_src . .
RUN mvn -q -pl agent-core,agent-memory-sdk,agent-mcp-client,agent-bundle,agent-engine,agent-runtime \
        -am package -DskipTests

# 2) Train a CDS archive: every agent boots the same jar (only the fetched bundle differs),
# so the class-loading work of a Spring Boot startup is identical across agents and only
# needs to be captured once, at image-build time — not baked-in per-agent state, just a
# cache of "which classes does this jar load on a normal boot". Boots against the bundled
# examples/hello-agent bundle in embedded mode (no Mongo/Redis, no network) and exits right
# after context refresh (spring.context.exit=onRefresh is Spring Boot's documented CDS
# training-run hook). A missing/mismatched archive is never fatal at runtime — the JVM logs
# a warning and boots without it — so this is a pure speed optimization, not a new failure mode.
FROM eclipse-temurin:25-jre-jammy AS trainer
WORKDIR /app
COPY --from=builder /src/agent-runtime/target/agent-runtime-*.jar /app/runtime.jar
COPY examples/hello-agent /training-bundle
RUN java -Dspring.context.exit=onRefresh -Dspring.profiles.active=embedded \
         -XX:ArchiveClassesAtExit=/app/app-cds.jsa \
         -jar /app/runtime.jar run /training-bundle

# 3) Runtime image (Jammy, not Alpine: ONNX semantic routing needs glibc).
FROM eclipse-temurin:25-jre-jammy
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
RUN groupadd --system gargantua && useradd --system --gid gargantua gargantua
WORKDIR /app
COPY --from=builder /src/agent-runtime/target/agent-runtime-*.jar /app/runtime.jar
COPY --from=trainer /app/app-cds.jsa /app/app-cds.jsa
# Cave's local-dev LLM/CORS defaults, picked up automatically by Spring Boot from
# ./config/application-{profile}.yml when `cave` is one of the active profiles — see
# runtime-cave.yml for why. Keeps Studio's launch command down to the bundle URL.
COPY runtime-cave.yml /app/config/application-cave.yml
RUN chown -R gargantua:gargantua /app
USER gargantua
EXPOSE 8080
ENTRYPOINT ["java", "-XX:SharedArchiveFile=/app/app-cds.jsa", "-jar", "/app/runtime.jar"]
CMD ["run"]
