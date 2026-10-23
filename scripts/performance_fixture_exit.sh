#!/bin/bash
# Sourced by owned-fixture drivers. The caller supplies its original exit status
# and the existing UUID-scoped cleanup command as distinct quoted arguments.
performance_fixture_exit() {
  local run_status="$1"
  shift
  trap - EXIT
  if [[ "$run_status" != '0' ]]; then
    printf '%s\n' 'Performance run failed or was interrupted; generated fixtures and recovery evidence were retained.' >&2
    exit "$run_status"
  fi
  local cleanup_status=0
  "$@" || cleanup_status=$?
  if [[ "$cleanup_status" != '0' ]]; then
    printf '%s\n' 'Performance fixture cleanup failed; inspect the retained manifest and owned app before continuing.' >&2
  fi
  exit "$cleanup_status"
}
