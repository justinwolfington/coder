# Base images - Last checked: 2026-08-28 (Chainguard via GAR cgr proxy, digest-pinned)
FROM us-docker.pkg.dev/abridge-artifact-registry/cgr/chainguard/go:latest@sha256:fe27e408146eadc3a39f8a35161349948d3494da4063f2361de5b586fdc23d39 AS build

WORKDIR /src
COPY docker/coder-user-data-transfer/ .
ENV CGO_ENABLED=0
RUN --mount=type=cache,target=/root/.cache/go-build go vet ./... && go test ./...
RUN --mount=type=cache,target=/root/.cache/go-build go build -trimpath -ldflags="-s -w" -o /tmp/coder-user-data-transfer .

FROM us-docker.pkg.dev/abridge-artifact-registry/cgr/chainguard/static:latest@sha256:77d8b8925dc27970ec2f48243f44c7a260d52c49cd778288e4ee97566e0cb75b
COPY --from=build /tmp/coder-user-data-transfer /coder-user-data-transfer
USER 65532:65532
ENTRYPOINT ["/coder-user-data-transfer"]
