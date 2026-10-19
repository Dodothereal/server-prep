#!/usr/bin/env bash
# Cap the memory of all GitHub Actions runners to 40% of RAM, so at least 60% stays free
# for the system, Docker and the deployed apps.
#
#   sudo ./limit-runners-memory.sh            # apply (default: runners share 40% of RAM)
#   sudo ./limit-runners-memory.sh 30%        # other share
#   sudo ./limit-runners-memory.sh --remove   # undo
#
# All runners are moved into one systemd slice (actions-runners.slice):
#   MemoryHigh = share - 5%  -> above this the kernel slows jobs down and reclaims memory
#   MemoryMax  = share       -> hard limit: a job going over it is killed, the rest of the machine is not touched
#   MemorySwapMax = 1G       -> jobs cannot push everything else into swap
# Each runner also gets its own MemoryMax so one heavy job cannot starve the other runners.
set -u

[[ $EUID -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }

SLICE=actions-runners.slice
DROPIN=50-memory-limit.conf
mapfile -t UNITS < <(systemctl list-unit-files 'actions.runner.*' --no-legend | awk '{print $1}')
[[ ${#UNITS[@]} -gt 0 ]] || { echo "No actions.runner.* service found" >&2; exit 1; }

busy() { pgrep -f Runner.Worker >/dev/null; }

if [[ "${1:-}" == "--remove" ]]; then
    for u in "${UNITS[@]}"; do rm -f "/etc/systemd/system/$u.d/$DROPIN"; done
    rm -f "/etc/systemd/system/$SLICE"
    systemctl daemon-reload
    echo "Limits removed. Restart the runners to apply: systemctl restart ${UNITS[*]}"
    exit 0
fi

SHARE="${1:-40%}"
[[ "$SHARE" =~ ^([1-9][0-9]?)%$ ]] || { echo "Share must be a percentage like 40%" >&2; exit 1; }
PCT=${BASH_REMATCH[1]}
TOTAL_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
N=${#UNITS[@]}
# per runner: half of the shared budget (two big jobs at once still fit), at least 1G
PER_MB=$(( TOTAL_KB * PCT / 100 / 1024 / 2 ))
(( PER_MB < 1024 )) && PER_MB=1024

cat > "/etc/systemd/system/$SLICE" <<EOF
# Managed by limit-runners-memory.sh - all GitHub Actions runners share this budget
[Unit]
Description=GitHub Actions runners (memory-limited)

[Slice]
MemoryAccounting=yes
MemoryHigh=$(( PCT - 5 ))%
MemoryMax=${PCT}%
MemorySwapMax=1G
EOF

for u in "${UNITS[@]}"; do
    mkdir -p "/etc/systemd/system/$u.d"
    cat > "/etc/systemd/system/$u.d/$DROPIN" <<EOF
# Managed by limit-runners-memory.sh
[Service]
Slice=$SLICE
MemoryMax=${PER_MB}M
MemorySwapMax=512M
OOMPolicy=continue
EOF
done
systemctl daemon-reload

echo "Runners: $N | shared limit: ${PCT}% of $(( TOTAL_KB / 1024 / 1024 ))G (soft $(( PCT - 5 ))%) | per runner: ${PER_MB}M"

if busy; then
    echo "A job is running now: restart later with:  sudo systemctl restart ${UNITS[*]}"
else
    systemctl restart "${UNITS[@]}"
    echo "Runners restarted."
fi

echo
systemctl show -p Id,Slice,MemoryMax "${UNITS[@]}" | paste - - - - | awk '{print $1, $2, $3}'
echo "Slice: $(systemctl show -p MemoryMax,MemoryHigh --value $SLICE | paste -sd' ')"
echo "Check usage anytime: systemd-cgtop $SLICE   or   systemctl status $SLICE"
