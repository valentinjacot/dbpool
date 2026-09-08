# Runtime image for the AppDynamics Machine Agent. The agent bundle itself
# (bin/machine-agent, machineagent.jar, bundled JRE) is bind-mounted at
# runtime from ./agents/machine-agent (see docker-compose.yml) - it is a
# licensed binary and not baked into this image or committed to git.
FROM debian:bookworm-slim

# findutils/procps: the launcher script and sigar-based hardware metrics
# collection shell out to find/ps. ca-certificates: TLS to the controller.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        findutils \
        procps \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/appdynamics/machine-agent
