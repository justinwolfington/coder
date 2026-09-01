# Coder exectrace for process monitoring - Last checked: 2026-08-31
#
# Upstream ships this on ubuntu:latest. exectrace is the only privileged
# container in a workspace pod, so it carries the whole Ubuntu package surface
# into the most sensitive place in the fleet. The binary declares exactly one
# dynamic dependency (DT_NEEDED libc.so.6, interpreter
# /lib64/ld-linux-x86-64.so.2) because the eBPF objects are linked in, so a
# glibc runtime is all it needs.
#
# The upstream binary is reused rather than rebuilt: exectrace's enterprise
# licence permits derivative works but forbids obscuring its notices, which the
# labels below preserve.
FROM ghcr.io/coder/exectrace:latest@sha256:88f8922697b6a30c89e848d066fd761a32537d722a32ac080bf1696256d325dd AS upstream

FROM us-docker.pkg.dev/abridge-artifact-registry/cgr/chainguard/glibc-dynamic:latest@sha256:d0046044cd28948d3380eb0d98709dc7e63f98161fe7105135e1025650bad17a

LABEL last_verified="2026-08-31" \
	org.opencontainers.image.title="Coder v2 Exectrace" \
	org.opencontainers.image.description="A tool for tracing launched processes inside Coder workspaces." \
	org.opencontainers.image.url="https://github.com/coder/exectrace/enterprise" \
	org.opencontainers.image.source="https://github.com/coder/exectrace/enterprise"

COPY --from=upstream /opt/exectrace /opt/exectrace

# Attaching kernel probes needs root; glibc-dynamic defaults to uid 65532.
USER 0:0
WORKDIR /
ENTRYPOINT ["/opt/exectrace", "run"]
