# Custom Arize Phoenix Dockerfile based on official image
FROM arizephoenix/phoenix:latest

# Set all environment variables needed for our deployment
ENV NODE_ENV=production \
    PHOENIX_PORT=6006 \
    PHOENIX_GRPC_PORT=4317 \
    PHOENIX_WORKING_DIR=/tmp/phoenix \
    PHOENIX_HOST=0.0.0.0 \
    OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://localhost:6006/v1/traces \
    PF_TRACING_SKIP_EXPORTER_SETUP=true \
    PF_TRACING_SKIP_LOCAL_SETUP=true \
    PF_DISABLE_TRACING=false

# Install curl for health checks (if not already present)
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/* || true

# Create working directory and set permissions
RUN mkdir -p ${PHOENIX_WORKING_DIR} && \
    chmod 755 ${PHOENIX_WORKING_DIR}

# Switch back to the default user (or create one if needed)
# The official Phoenix image may already have a user, so we'll use that
USER ${PHOENIX_USER:-1000}

# Set working directory
WORKDIR ${PHOENIX_WORKING_DIR}

# Expose ports
EXPOSE ${PHOENIX_PORT} ${PHOENIX_GRPC_PORT}

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:${PHOENIX_PORT}/ || exit 1

# Use the default command from the base image
# This will inherit the CMD from arizephoenix/phoenix:latest
