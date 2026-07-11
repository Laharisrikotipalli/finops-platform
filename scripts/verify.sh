#!/usr/bin/env bash
set -uo pipefail

FAILED=0

check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS: ${description}"
  else
    echo "FAIL: ${description}"
    FAILED=1
  fi
}

echo "== Verifying required namespaces =="
for ns in kubecost monitoring goldilocks default; do
  check "namespace ${ns} exists" kubectl get namespace "${ns}"
done

echo "== Verifying core workload pods are Running =="
check "kubecost pods running" bash -c \
  "[ \"\$(kubectl get pods -n kubecost --field-selector=status.phase=Running -o name | wc -l)\" -gt 0 ]"

check "prometheus pods running" bash -c \
  "[ \"\$(kubectl get pods -n monitoring -l app=prometheus-server --field-selector=status.phase=Running -o name | wc -l)\" -gt 0 ]"

check "grafana pods running" bash -c \
  "[ \"\$(kubectl get pods -n monitoring -l app=grafana --field-selector=status.phase=Running -o name | wc -l)\" -gt 0 ]"

check "goldilocks pods running" bash -c \
  "[ \"\$(kubectl get pods -n goldilocks --field-selector=status.phase=Running -o name | wc -l)\" -gt 0 ]"

echo "== Verifying VerticalPodAutoscaler resources =="
check "batch-job-vpa exists" kubectl get vpa batch-job-vpa -n default

echo "== Running cost report generation =="
check "generate-report.sh executes" bash "$(dirname "$0")/generate-report.sh"

if [ "${FAILED}" -eq 0 ]; then
  echo "All checks passed."
  exit 0
else
  echo "One or more checks failed."
  exit 1
fi
