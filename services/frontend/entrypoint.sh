#!/bin/sh
RESOLVER=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)
API_URL=${API_URL:-http://api.app.svc.cluster.local:3000}
sed "s/__RESOLVER__/$RESOLVER/g" /etc/nginx/conf.d/default.conf.template \
  | sed "s|__API_URL__|$API_URL|g" \
  > /etc/nginx/conf.d/default.conf
exec nginx -g 'daemon off;'
