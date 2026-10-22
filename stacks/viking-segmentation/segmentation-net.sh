#!/bin/sh
# Network holder for viking-segmentation on macvlan (compose.macvlan.yaml).
#
# Docker has already given eth0 the reserved IP and the reservation's MAC. This keeps a real DHCP
# lease for that MAC, so the DHCP server and any DHCP snooping on the switch see it, and reports in
# the log (and the healthcheck) when the server offers a different address than the reservation.
# It never exits on its own: segmentation-server shares this container's network namespace.
#
# Run without arguments it is the entrypoint; udhcpc calls it back with the event name
# (deconfig, bound, renew, leasefail, nak) and the lease in $ip, $lease, ...
set -u

state=/tmp/segmentation-net.bound
want="${SEGMENTATION_LAN_IP:?SEGMENTATION_LAN_IP must be set}"
mac="$(cat /sys/class/net/eth0/address 2>/dev/null || echo unknown)"

case "${1:-}" in
    deconfig)
        # udhcpc would flush eth0 here; keep Docker's address so the server keeps serving.
        rm -f "$state"
        exit 0 ;;
    bound|renew)
        if [ "${ip:-}" = "$want" ]; then
            echo "segmentation-net: DHCP $1: ${ip} for ${mac}, lease ${lease:-?} s"
            touch "$state"
        else
            echo "segmentation-net: ERROR: DHCP offered ${ip:-no address} to ${mac}, but the reservation should give ${want}." \
                "Fix the reservation; the container keeps ${want}." >&2
            rm -f "$state"
        fi
        exit 0 ;;
    leasefail|nak)
        echo "segmentation-net: DHCP $1 for ${mac}; keeping ${want}" >&2
        exit 0 ;;
    '') ;;
    *) exit 0 ;;
esac

child=''
trap '[ -n "$child" ] && kill "$child" 2>/dev/null; exit 0' TERM INT

if [ "${SEGMENTATION_DHCP:-1}" != "1" ]; then
    echo "segmentation-net: ${want} on ${mac}, static (SEGMENTATION_DHCP=${SEGMENTATION_DHCP}); no DHCP lease"
    while :; do
        sleep 3600 & child=$!
        wait "$child"
    done
fi

host="${SEGMENTATION_DHCP_HOSTNAME:-segmentation}"
# udhcpc execs its hook directly; the bind-mounted copy may lack the execute bit.
hook=/tmp/segmentation-net-hook.sh
cp "$0" "$hook" && chmod 755 "$hook"
echo "segmentation-net: ${want} on ${mac}; keeping a DHCP lease (hostname ${host})"
while :; do
    # -f foreground, retry every 60 s when no server answers, never give up; -r asks for the reserved IP.
    udhcpc -f -i eth0 -s "$hook" -r "$want" -x "hostname:${host}" -T 5 -t 4 -A 60 & child=$!
    wait "$child"
    echo "segmentation-net: udhcpc exited ($?); restarting in 10 s" >&2
    sleep 10 & child=$!
    wait "$child"
done
