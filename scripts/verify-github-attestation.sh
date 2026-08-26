#!/usr/bin/env bash

set -euo pipefail

if (( $# < 3 )); then
  echo "Usage: $0 OWNER/REPO .github/workflows/WORKFLOW.yml ARTIFACT..." >&2
  exit 64
fi

repository="$1"
signer_workflow="$2"
shift 2

if [[ ! "$repository" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "Invalid GitHub repository: $repository" >&2
  exit 64
fi

if [[ ! "$signer_workflow" =~ ^\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$ ]]; then
  echo "Invalid signer workflow path: $signer_workflow" >&2
  exit 64
fi

if [[ -z "${GITHUB_REF:-}" ]]; then
  echo "GITHUB_REF is required for source-ref verification." >&2
  exit 64
fi

for artifact in "$@"; do
  if [[ ! -f "$artifact" ]]; then
    echo "Attestation subject does not exist: $artifact" >&2
    exit 66
  fi

  verified=false
  for attempt in 1 2 3 4 5; do
    if gh attestation verify "$artifact" \
      --repo "$repository" \
      --signer-workflow "$repository/$signer_workflow" \
      --source-ref "$GITHUB_REF" \
      --deny-self-hosted-runners; then
      verified=true
      break
    fi

    if (( attempt < 5 )); then
      sleep $((attempt * 2))
    fi
  done

  if [[ "$verified" != true ]]; then
    echo "GitHub artifact attestation verification failed: $artifact" >&2
    exit 1
  fi
done
