# syntax=docker/dockerfile:1
ARG BUILD_IMAGE=golang:1.26
ARG RUNTIME_IMAGE=gcr.io/distroless/static:nonroot
FROM --platform=$BUILDPLATFORM ${BUILD_IMAGE} AS build
ARG TARGETOS=linux
ARG TARGETARCH
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY api api
COPY internal internal
COPY cmd cmd
COPY assets.go ./
COPY chart chart
ARG VERSION=dev
ARG IMAGE_PREFIX
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w -X shadok.org/operator/internal/buildinfo.Version=$VERSION -X shadok.org/operator/internal/buildinfo.ImagePrefix=$IMAGE_PREFIX" -o /out/operator ./cmd/operator \
 && CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w -X shadok.org/operator/internal/buildinfo.Version=$VERSION -X shadok.org/operator/internal/buildinfo.ImagePrefix=$IMAGE_PREFIX" -o /out/gateway ./cmd/gateway \
 && CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w -X shadok.org/operator/internal/buildinfo.Version=$VERSION -X shadok.org/operator/internal/buildinfo.ImagePrefix=$IMAGE_PREFIX" -o /out/shadok ./cmd/shadok

FROM ${RUNTIME_IMAGE} AS runtime
ARG VERSION=dev
LABEL org.opencontainers.image.licenses="MIT" org.opencontainers.image.source="https://github.com/ng-galien/shadok" org.opencontainers.image.title="Shadok" org.opencontainers.image.version=$VERSION
COPY chart/LICENSE /usr/share/licenses/shadok/LICENSE
USER 65532:65532

FROM runtime AS tools
COPY --from=build /out/shadok /shadok
ENTRYPOINT ["/shadok"]

FROM runtime AS gateway
COPY --from=build /out/gateway /gateway
EXPOSE 8080
ENTRYPOINT ["/gateway"]

FROM runtime AS operator
COPY --from=build /out/operator /operator
EXPOSE 9000
ENTRYPOINT ["/operator"]
