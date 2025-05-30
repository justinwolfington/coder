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

# Set working directory
WORKDIR ${PHOENIX_WORKING_DIR}

# Expose ports
EXPOSE ${PHOENIX_PORT} ${PHOENIX_GRPC_PORT}

# Use the default command from the base image
# This will inherit the CMD from arizephoenix/phoenix:latest
