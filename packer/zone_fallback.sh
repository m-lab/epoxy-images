#!/bin/bash
#
# Shared helper for running `packer build` with automatic GCP zone fallback.
#
# Packer must create a temporary builder VM to produce each image, and lately we
# frequently hit ZONE_RESOURCE_POOL_EXHAUSTED when a single GCP zone is out of
# capacity for the builder's machine type. This helper tries a list of candidate
# zones (spread across several US regions, all reachable on the default
# auto-mode network) until one succeeds. It only advances to the next zone on a
# capacity error; any other failure is a real build error and aborts
# immediately, so genuine bugs are not masked by silently cycling through zones.
#
# Override the candidate list by exporting $PACKER_ZONES (space-separated).
#
# Usage (from within the packer/ directory):
#   source ./zone_fallback.sh
#   packer_build_with_zone_fallback <template.pkr.hcl> [extra packer build args...]

PACKER_ZONES="${PACKER_ZONES:-us-central1-c us-central1-a us-central1-b us-central1-f us-east1-b us-east1-c us-east1-d us-east4-a us-east4-b us-east4-c us-west1-a us-west1-b us-west1-c}"

packer_build_with_zone_fallback() {
  local template="$1"; shift
  local zone build_log pstatus

  for zone in $PACKER_ZONES; do
    echo "=== Attempting Packer build of ${template} in zone: ${zone} ==="
    build_log="$(mktemp)"

    # Use PIPESTATUS to read packer's exit code rather than tee's.
    packer build -force -var "zone=${zone}" "$@" "${template}" 2>&1 | tee "${build_log}"
    pstatus="${PIPESTATUS[0]}"

    if [[ "${pstatus}" -eq 0 ]]; then
      echo "=== Packer build of ${template} succeeded in zone: ${zone} ==="
      rm -f "${build_log}"
      return 0
    fi

    # Packer surfaces zone capacity exhaustion as the human-readable GCE message
    # "does not have enough resources available", not the raw
    # ZONE_RESOURCE_POOL_EXHAUSTED error code. Match either, case-insensitively.
    if grep -qiE "does not have enough resources|ZONE_RESOURCE_POOL_EXHAUSTED" "${build_log}"; then
      echo "=== Zone ${zone} has no capacity; trying the next zone ==="
      rm -f "${build_log}"
      continue
    fi

    echo "=== Packer build of ${template} failed in zone ${zone} for a non-capacity reason (exit ${pstatus}); aborting ==="
    rm -f "${build_log}"
    return "${pstatus}"
  done

  echo "=== ERROR: Packer build of ${template} did not succeed in any candidate zone ==="
  return 1
}
