#!/bin/sh
set -e
# Si ECS inyecta PEM por variables (Secrets Manager → env), genera ficheros y apunta JWT ahí.
if [ -n "${JWT_PUBLIC_PEM:-}" ] && [ -n "${JWT_PRIVATE_PEM:-}" ]; then
  umask 077
  printf '%s\n' "$JWT_PUBLIC_PEM" > /tmp/mp-jwt-public.pem
  printf '%s\n' "$JWT_PRIVATE_PEM" > /tmp/mp-jwt-private.pem
  export JAVA_OPTS_APPEND="${JAVA_OPTS_APPEND} -Dmp.jwt.verify.publickey.location=/tmp/mp-jwt-public.pem -Dsmallrye.jwt.sign.key.location=/tmp/mp-jwt-private.pem"
fi
exec /opt/jboss/container/java/run/run-java.sh "$@"
