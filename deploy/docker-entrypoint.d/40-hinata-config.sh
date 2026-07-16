#!/bin/sh
# Regenerate the runtime config from the container environment.
# The shipped image bakes NO backend; the operator sets HINATA_DEFAULT_SERVER in
# the deployment (compose/stack env). Unset/empty ⇒ the app shows /connect.
#
# nginx:alpine runs every executable *.sh in /docker-entrypoint.d before it
# starts nginx, so no custom ENTRYPOINT is needed.
set -eu

: "${HINATA_DEFAULT_SERVER:=}"

# Escape backslash and double-quote so the value stays a valid JS string literal.
esc_server=$(printf '%s' "$HINATA_DEFAULT_SERVER" | sed 's/[\\"]/\\&/g')

cat > /usr/share/nginx/html/config.js <<EOF
// Generated at container start from \$HINATA_DEFAULT_SERVER — do not edit.
window.hinataDefaultServer = "${esc_server}";
EOF

echo "hinata: config.js -> hinataDefaultServer='${HINATA_DEFAULT_SERVER}'"

# --- Hinata Connect domain-control challenge --------------------------------
# The Connect gateway proves the operator controls BOTH registered origins (API
# + web) by fetching /.well-known/hinata-connect-challenge before it enables
# the deep-link web fallback. The API server serves the nonce itself; this web
# container simply proxies that one path through to the configured backend, so
# both origins answer with the same value. Only generated when a backend is
# configured and the include is referenced by nginx.conf.
CHALLENGE_CONF=/etc/nginx/conf.d/hinata-challenge.inc
API_ORIGIN=$(printf '%s' "$HINATA_DEFAULT_SERVER" | sed 's#/*$##')
if [ -n "$API_ORIGIN" ]; then
  cat > "$CHALLENGE_CONF" <<EOF
# Generated at container start from \$HINATA_DEFAULT_SERVER — do not edit.
location = /.well-known/hinata-connect-challenge {
    proxy_pass ${API_ORIGIN}/.well-known/hinata-connect-challenge;
    proxy_ssl_server_name on;
    proxy_set_header Host \$proxy_host;
    proxy_connect_timeout 4s;
    proxy_read_timeout 4s;
    add_header Cache-Control "no-store";
}
EOF
  echo "hinata: challenge proxy -> ${API_ORIGIN}"
else
  # No backend configured: keep the include valid but empty (404 via SPA route).
  : > "$CHALLENGE_CONF"
fi
