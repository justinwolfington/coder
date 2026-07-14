# Base images - Last checked: 2026-07-07 (Chainguard via GAR cgr proxy, digest-pinned)
FROM us-docker.pkg.dev/abridge-artifact-registry/cgr/chainguard/go:latest@sha256:fe27e408146eadc3a39f8a35161349948d3494da4063f2361de5b586fdc23d39 AS build

# Label to track last verification date (forces rebuild when updated)
LABEL last_verified="2026-07-07"

WORKDIR /src
COPY docker/langsmith-proxy/ .
# CGO_ENABLED set once so vet/test/build share build-cache entries
ENV CGO_ENABLED=0
RUN --mount=type=cache,target=/root/.cache/go-build go vet ./... && go test ./...
RUN --mount=type=cache,target=/root/.cache/go-build go build -trimpath -ldflags="-s -w" -o /tmp/langsmith-proxy .

FROM us-docker.pkg.dev/abridge-artifact-registry/cgr/chainguard/static:latest@sha256:77d8b8925dc27970ec2f48243f44c7a260d52c49cd778288e4ee97566e0cb75b
COPY --from=build /tmp/langsmith-proxy /langsmith-proxy
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/langsmith-proxy"]
