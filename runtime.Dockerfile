# Gargantua Runtime image WITH a demo bundle baked in.
#
# Why not just bind-mount the bundle (as the stock agent-runtime image expects via
# GARGANTUA_BUNDLE=/bundle)? Because in Cave the Docker daemon is remote — a bind mount
# of a workspace path resolves on the daemon's host, which can't see this repo, so it
# arrives empty. A build-time COPY works: the build context is streamed to the daemon.
#
# Build context is THIS repo (for the ./examples bundle); the Runtime source is supplied
# as the named context `runtime_src` (= ../gargantua), same pattern as the other images.

# 1) Build the runtime jar from source.
FROM maven:3.9-eclipse-temurin-25-alpine AS builder
WORKDIR /src
COPY --from=runtime_src . .
RUN mvn -q -pl agent-core,agent-memory-sdk,agent-mcp-client,agent-bundle,agent-engine,agent-runtime \
        -am package -DskipTests

# 2) Runtime image (Jammy, not Alpine: ONNX semantic routing needs glibc) + baked bundle.
FROM eclipse-temurin:25-jre-jammy
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*
RUN groupadd --system gargantua && useradd --system --gid gargantua gargantua
WORKDIR /app
COPY --from=builder /src/agent-runtime/target/agent-runtime-*.jar /app/runtime.jar
# The demo bundle, baked in (from this repo's build context).
COPY examples/hello-agent /bundle
RUN chown -R gargantua:gargantua /app /bundle
USER gargantua
ENV GARGANTUA_BUNDLE=/bundle
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/runtime.jar"]
CMD ["run"]
