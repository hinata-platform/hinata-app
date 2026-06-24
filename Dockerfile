# ---- Build stage: compile the Flutter web app ----
FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /app

# Backend the hosted web build talks to by default (so users skip the connect
# screen). Override at build time: --build-arg HINATA_DEFAULT_SERVER=...
ARG HINATA_DEFAULT_SERVER=https://api.track.asta.hn

# Warm the pub cache on the dependency manifest before copying the full source.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release \
    --dart-define=HINATA_DEFAULT_SERVER=${HINATA_DEFAULT_SERVER}

# ---- Runtime stage: serve the static build via nginx ----
FROM nginx:1.27-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
# Deep-link association files (Option B). Served from the web root so
# https://track.asta.hn/.well-known/* verifies Android App Links + iOS
# Universal Links. assetlinks.json carries the release signing fingerprint.
COPY deploy/well-known/ /usr/share/nginx/html/.well-known/
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD wget -qO- http://127.0.0.1/ >/dev/null 2>&1 || exit 1
