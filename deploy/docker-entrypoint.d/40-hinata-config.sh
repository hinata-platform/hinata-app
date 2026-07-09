#!/bin/sh
# Regenerate the white-label runtime config from the container environment.
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
