ARG UPSTREAM_IMAGE
FROM ${UPSTREAM_IMAGE}

ARG SOURCE_MIRROR_COMMIT
LABEL org.opencontainers.image.source="https://github.com/abridgeai/coder-upstream" \
	org.opencontainers.image.revision="${SOURCE_MIRROR_COMMIT}"

COPY --chown=1000:1000 --chmod=0755 coder /opt/coder
