# Multi-stage build for demo-app
# Stage 1: Build (uses official Go image with full toolchain)
# Stage 2: Runtime (distroless static image - minimal attack surface)
#
# Both images support linux/arm64 natively.
# Distroless static: https://github.com/GoogleContainerTools/distroless
# golang: https://hub.docker.com/_/golang

# ------- Build stage -------
FROM docker.io/library/golang:1.22-alpine AS builder

WORKDIR /src

# Copy dependency files first for layer caching
COPY go.mod ./

# Download dependencies (none in this app, but keep pattern consistent)
RUN go mod download

# Copy source
COPY main.go ./

# Build a statically linked binary for the target platform.
# CGO_ENABLED=0 is required for distroless/static which has no libc.
# -trimpath removes local path references from debug info.
# -ldflags="-s -w" strips debug symbols to reduce binary size.
RUN CGO_ENABLED=0 GOOS=linux \
    go build \
      -trimpath \
      -ldflags="-s -w" \
      -o /demo-app \
      main.go

# ------- Runtime stage -------
# gcr.io/distroless/static supports linux/arm64 and linux/amd64.
# 'nonroot' variant runs as UID 65532 (nonroot user) by default.
# No shell, no package manager, no libc - minimal attack surface.
FROM gcr.io/distroless/static:nonroot

# Copy binary from builder
COPY --from=builder /demo-app /demo-app

# Run as nonroot (UID 65532 in distroless/static:nonroot)
USER nonroot:nonroot

EXPOSE 8080

ENTRYPOINT ["/demo-app"]
