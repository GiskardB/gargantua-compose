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

# 2) Runtime image (Jammy, not Alpine: ONNX semantic routing needs glibc).
FROM eclipse-temurin:25-jre-jammy
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
RUN groupadd --system gargantua && useradd --system --gid gargantua gargantua
WORKDIR /app
COPY --from=builder /src/agent-runtime/target/agent-runtime-*.jar /app/runtime.jar
# Cave's local-dev LLM/CORS defaults, picked up automatically by Spring Boot from
# ./config/application-{profile}.yml when `cave` is one of the active profiles — see
# runtime-cave.yml for why. Keeps Studio's launch command down to the bundle URL.
COPY runtime-cave.yml /app/config/application-cave.yml
RUN chown -R gargantua:gargantua /app
USER gargantua
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/runtime.jar"]
CMD ["run"]
