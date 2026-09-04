#!/bin/bash
set -e

rm -f "${PWD}/tmp/pids/server.pid"

exec "$@"
