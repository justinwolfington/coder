# Custom Arize Phoenix Dockerfile based on official image - 20/11/2025
FROM arizephoenix/phoenix:latest

# Set all environment variables needed for our deployment
# https://arize.com/docs/phoenix/self-hosting/configuration
ENV NODE_ENV=production \
    PHOENIX_PORT=6006 \
    PHOENIX_GRPC_PORT=4317 \
    PHOENIX_WORKING_DIR=/tmp/phoenix

# Set working directory
WORKDIR ${PHOENIX_WORKING_DIR}

# Expose ports
EXPOSE ${PHOENIX_PORT} ${PHOENIX_GRPC_PORT}

# Use the default command from the base image
# This will inherit the CMD from arizephoenix/phoenix:latest
