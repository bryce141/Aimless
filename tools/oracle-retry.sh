#!/usr/bin/env bash
#
# Chases Oracle free-tier ARM capacity until it wins.
#
# "Out of host capacity" on VM.Standard.A1.Flex is not a misconfiguration and
# not something retrying by hand fixes reliably — free ARM frees up in windows
# of seconds, at unpredictable times, and whoever is asking at that moment gets
# it. So ask continuously.
#
# Rotates through every availability domain in the region, because capacity is
# tracked per-AD and each one is an independent draw.
#
# Stops immediately on any error that is NOT capacity — a bad OCID or an expired
# key would otherwise spin for days looking like bad luck.
#
#   ./oracle-retry.sh              # 2 OCPU / 12 GB, the full free allowance
#   OCPUS=1 MEM=6 ./oracle-retry.sh    # smaller, fits fragmented capacity
#
set -uo pipefail

OCPUS="${OCPUS:-2}"
MEM="${MEM:-12}"
BOOT_GB="${BOOT_GB:-50}"
SLEEP="${SLEEP:-60}"
NAME="${NAME:-aimless-ors}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/aimless_oracle.pub}"

command -v oci >/dev/null || { echo "oci CLI not found. brew install oci-cli"; exit 1; }
[[ -f "$SSH_KEY" ]] || { echo "No SSH public key at $SSH_KEY"; exit 1; }

echo "Resolving tenancy..."
TENANCY=$(oci iam compartment list --access-level ACCESSIBLE --compartment-id-in-subtree true \
          --query 'data[0]."compartment-id"' --raw-output 2>/dev/null) \
  || TENANCY=$(grep -E '^tenancy' ~/.oci/config | head -1 | cut -d= -f2 | tr -d ' ')
COMPARTMENT="${COMPARTMENT:-$TENANCY}"

# Ubuntu 24.04 for aarch64. Queried rather than hardcoded: Oracle publishes new
# image builds constantly and a stale OCID fails in a way that looks like
# anything but a stale OCID.
echo "Finding Ubuntu 24.04 aarch64 image..."
IMAGE=$(oci compute image list --compartment-id "$COMPARTMENT" \
        --operating-system "Canonical Ubuntu" --operating-system-version "24.04" \
        --shape VM.Standard.A1.Flex --sort-by TIMECREATED \
        --query 'data[0].id' --raw-output)
[[ -n "$IMAGE" && "$IMAGE" != "null" ]] || { echo "No Ubuntu 24.04 ARM image found"; exit 1; }

# The subnet the console already created. Public, so SSH works.
echo "Finding subnet..."
SUBNET=$(oci network subnet list --compartment-id "$COMPARTMENT" \
         --query 'data[?"prohibit-public-ip-on-vnic"==`false`] | [0].id' --raw-output)
[[ -n "$SUBNET" && "$SUBNET" != "null" ]] || {
  echo "No public subnet found. Create the VCN in the console first."; exit 1; }

# Plain read loop rather than mapfile: macOS ships bash 3.2, where mapfile
# does not exist and the failure is an empty array rather than an error.
ADS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && ADS+=("$line")
done < <(oci iam availability-domain list --compartment-id "$COMPARTMENT" \
         --query 'data[].name' --raw-output | tr -d '[]," ' | grep -v '^$')
[[ ${#ADS[@]} -gt 0 ]] || { echo "No availability domains found"; exit 1; }

cat <<EOF

  shape      VM.Standard.A1.Flex  ${OCPUS} OCPU / ${MEM} GB
  boot       ${BOOT_GB} GB
  image      ${IMAGE:0:40}...
  subnet     ${SUBNET:0:40}...
  domains    ${#ADS[@]}
  interval   ${SLEEP}s

Ctrl-C to stop.

EOF

attempt=0
while true; do
  for AD in "${ADS[@]}"; do
    attempt=$((attempt + 1))
    printf '[%s] attempt %-4d %s ... ' "$(date +%H:%M:%S)" "$attempt" "${AD##*:}"

    OUT=$(oci compute instance launch \
      --availability-domain "$AD" \
      --compartment-id "$COMPARTMENT" \
      --shape VM.Standard.A1.Flex \
      --shape-config "{\"ocpus\":${OCPUS},\"memoryInGBs\":${MEM}}" \
      --image-id "$IMAGE" \
      --subnet-id "$SUBNET" \
      --boot-volume-size-in-gbs "$BOOT_GB" \
      --assign-public-ip true \
      --display-name "$NAME" \
      --metadata "{\"ssh_authorized_keys\":\"$(cat "$SSH_KEY")\"}" \
      --wait-for-state RUNNING 2>&1)

    if [[ $? -eq 0 ]]; then
      ID=$(echo "$OUT" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["id"])' 2>/dev/null)
      echo "GOT ONE"
      echo
      IP=$(oci compute instance list-vnics --instance-id "$ID" \
           --query 'data[0]."public-ip"' --raw-output 2>/dev/null)
      echo "  instance  $ID"
      echo "  public IP $IP"
      echo
      echo "  ssh -i ~/.ssh/aimless_oracle ubuntu@$IP"
      echo
      command -v osascript >/dev/null && \
        osascript -e "display notification \"$IP\" with title \"Oracle instance is up\"" 2>/dev/null
      exit 0
    fi

    # Capacity is the expected failure. Anything else is a real problem and
    # retrying it for three days would just hide it.
    if echo "$OUT" | grep -qi "out of host capacity\|out of capacity"; then
      echo "no capacity"
    else
      echo "FAILED"
      echo
      echo "$OUT" | head -20
      echo
      echo "Not a capacity error — stopping so this doesn't spin on a real fault."
      exit 1
    fi
  done
  sleep "$SLEEP"
done
