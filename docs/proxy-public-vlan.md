# viking-proxy on the public VLAN

Give `viking-proxy` its own MAC address and IP on the public-facing VLAN while the host stays on its own VLAN.
At Pitt the public VLAN is 1811 (10.227.66.224/27): `connectomes.pitt.edu` is the proxy at 10.227.66.253, and the
segmentation server is at 10.227.66.252 (`docs/segmentation-host.md`). Linux hosts only.

What you end up with:

- `viking-proxy` answering on `<IP>:80/443` on the public VLAN, with its default route through that VLAN's gateway,
  so public replies and remote upstreams (segmentation) use it.
- Nothing published on the host (Docker publishes only on the gateway endpoint, which is now the macvlan). The
  health check runs inside the container. The host's own address no longer serves the proxy.
- The proxy's bridge network kept, so stacks on the same host stay reachable as `host.docker.internal`.

Needs Docker Engine 28+ and Compose 2.33+ (`gw_priority`).

## 1. Network prerequisites

At Pitt (2026-11-18) the public VLAN is already trunked to the hosts' ports and any MAC is accepted. Use a static
`<IP>` on that VLAN; DHCP reservations come later. Elsewhere, ask IT for:

1. The public VLAN trunked (tagged) to the host's switch ports (on HypV1: bond `external` = eno1+eno2).
2. A second MAC allowed on those ports (port security), if port security is on: `<MAC>`, locally administered
   (`02:...`, not `02:42:...`).
3. Inbound TCP 80 and 443 from the internet to `<IP>` (or the public NAT for it). Upstreams on the same VLAN
   (segmentation `10.227.66.252:443`) need no extra rule.
4. Public DNS for the proxy names (`connectomes.pitt.edu`, `segmentation.connectomes.pitt.edu`) to `<IP>`'s public
   address.

## 2. Settings

In `Run/viking-proxy/viking-proxy.run.env`:

```
STACK_COMPOSE_OVERLAYS=stacks/viking-proxy/compose.macvlan.yaml
PROXY_MACVLAN_PARENT=external.1811
PROXY_LAN_SUBNET=10.227.66.224/27
PROXY_LAN_GATEWAY=10.227.66.225
PROXY_LAN_IP=10.227.66.253
PROXY_MAC_ADDRESS=<MAC>
STACK_HEALTH_EXEC_SERVICE=viking-proxy
```

`PROXY_MACVLAN_PARENT` is a host NIC or `<nic>.<vlan id>`; Docker creates the 802.1Q sub-interface when it is
missing, so no netplan change is needed.

## 3. Switch over

```
stack doctor
stack viking-proxy up
stack viking-proxy status
```

Check:

- From another machine on the VLAN: `curl -kI https://10.227.66.253/` answers. The host itself cannot reach a
  macvlan IP, so don't test from it.
- `stack doctor` probes each upstream from inside the proxy container once the overlay is on; every upstream
  should be `OK`.
- Public: `curl -I http://connectomes.pitt.edu/` reaches the proxy (needed for Let's Encrypt HTTP-01).

## Rollback

Comment out the `STACK_COMPOSE_OVERLAYS` line and run `stack viking-proxy up`. The proxy goes back to the host's
ports on its own VLAN.
