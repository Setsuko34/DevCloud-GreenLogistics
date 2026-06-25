#!/bin/sh
RESOLVER=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf)
sed "s/__RESOLVER__/$RESOLVER/g" /etc/nginx/conf.d/default.conf.template \
  > /etc/nginx/conf.d/default.conf
exec nginx -g 'daemon off;'
