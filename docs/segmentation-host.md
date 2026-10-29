# New segmentation host on its own MAC and IP

Bring up the Viking segmentation server (`segmentation-server`, the GPU gRPC service Viking clients
use) on a new Linux host, in a container with its own MAC address and an IP from a DHCP reservation,
then move `segmentation.<domain>` to it from the old compute host.

What you end up with:

- `segmentation-server` listening on `<IP>:443`, the reserved IP. Nothing is published on the host.
- A small `segmentation-net` container that holds that network and keeps a DHCP lease for the MAC.
- `viking-proxy` on the web host sending `segmentation.<domain>` to `<IP>:443`. Clients don't change.

Placeholders used below:

| Placeholder | Meaning | Example |
|---|---|---|
| `<newhost>` | the new server's own hostname | `seg1.connectomes.pitt.edu` |
| `<MAC>` | the container's MAC address | `02:5e:10:00:00:01` |
| `<IP>` | the IP IT reserves for `<MAC>` | `10.20.30.40` |
| `<nic>` | the new host's wired NIC on that LAN | `eno1` |
| `web`, `compute` | the web host (proxy) and the old compute host | |

Run commands on the new host unless a step says otherwise. `stack` is the alias for
`pwsh /srv/docker/stack.ps1` that step 4 creates.

## Before you start

- **Hardware:** a bare-metal host with an NVIDIA GPU and a wired NIC on the LAN, running Ubuntu 24.04
  or 26.04. Docker Desktop and Wi-Fi interfaces can't do this (macvlan).
- **Access:** your login on the new host. It must be able to sudo, and it becomes the deploy user that
  runs `stack.ps1`. You also need SSH to `web` and `compute`; the commands below write `deploy@web` and
  `deploy@compute` for your account on those hosts.
- **Image:** the steps pull the prebuilt `ghcr.io/jamesra/viking-segmentation-server` image. While that
  GHCR package is private, the host needs a GitHub token with `read:packages` (step 6).

## 1. Choose a MAC and ask IT

Pick a locally administered unicast MAC: first byte `02`, but not `02:42`, which Docker uses for its
own containers. On any Linux machine:

```bash
printf 02; od -An -N5 -tx1 /dev/urandom | tr ' ' ':'
```

Ask IT (one ticket) for:

1. A DHCP reservation of an IP for `<MAC>`, with the hostname you want registered.
2. The switch port of `<newhost>` to allow a second MAC address (port security): the host's NIC and
   the container both use it.
3. Network ACLs: inbound TCP 443 to `<IP>` from the web host (`viking-proxy`); outbound from `<IP>`
   to the identity and websvc hosts if the server reads local tilesets.

Note the IP, the subnet (e.g. `10.20.30.0/24`) and the gateway.

## 2. Prepare the host

```bash
sudo ubuntu-drivers install && sudo reboot
```

After the reboot, `nvidia-smi` must list the GPU. Then:

```bash
curl -fsSL https://raw.githubusercontent.com/jamesra/connectomes-deploy/main/bootstrap-ubuntu.sh -o bootstrap-ubuntu.sh
sudo bash bootstrap-ubuntu.sh --gpu
```

Run it from your own login: that account becomes the deploy user. For a dedicated account instead,
create it first (`sudo adduser deploy`), add `--user deploy`, and do the remaining steps logged in as it.

This installs Docker, PowerShell 7 and the NVIDIA container toolkit, and creates `/srv/docker`,
`/srv/connectomes-deploy` and `/srv/src`. Log out and back in (docker group). Check that Docker is 25
or newer: `docker version --format '{{.Server.Version}}'`.

## 3. Get the code

```bash
git clone https://github.com/jamesra/connectomes-deploy.git /srv/connectomes-deploy
git clone -b dev https://github.com/jamesra/Viking.git /srv/src/Viking
```

Viking is needed only for its compose files while they still live there; with the prebuilt image nothing
is built from it.

## 4. Create the host layout

```bash
pwsh /srv/connectomes-deploy/Initialize-DockerHost.ps1 -Root /srv/docker -Role compute \
  -Stacks viking-segmentation,viking-certs -VikingRepoRoot /srv/src/Viking -SetUserEnv
```

It creates `/srv/docker/Run/...`, copies the templates, writes the `/srv/docker/stack.ps1` launcher and
adds the `stack` alias to `~/.profile`. The `doctor` it runs at the end reports the settings you have
not filled in yet. Log out and back in for the alias.

## 5. Configure

### 5a. Host settings

In `/srv/docker/Run/_host/host.env`:

- `VIKING_DOMAIN=connectomes.pitt.edu`
- `TLS_MODE=manual` (this host receives the certificate from `web`; it does not request one)

Leave `VIKING_COMPUTE_HOST` and `VIKING_IIS_HOST` empty: they are web-host settings.

### 5b. Segmentation settings

Start from the old host's settings, so the identity client and tuning carry over:

```bash
scp deploy@compute:/srv/docker/Run/viking-segmentation/viking-segmentation.run.env \
    /srv/docker/Run/viking-segmentation/
scp -r deploy@compute:/srv/docker/Run/viking-segmentation/secrets/. \
    /srv/docker/Run/viking-segmentation/secrets/
chmod 700 /srv/docker/Run/viking-segmentation/secrets
```

Find the NIC, subnet and gateway:

```bash
ip -br link                 # the wired NIC, e.g. eno1
ip -4 -br addr show eno1    # the host's address and prefix, e.g. 10.20.30.15/24 -> 10.20.30.0/24
ip route show default       # the gateway
```

Append to `/srv/docker/Run/viking-segmentation/viking-segmentation.run.env`:

```bash
# Own MAC address and IP (connectomes-deploy docs/segmentation-host.md)
STACK_COMPOSE_OVERLAYS=stacks/viking-segmentation/compose.macvlan.yaml
SEGMENTATION_MACVLAN_PARENT=<nic>
SEGMENTATION_LAN_SUBNET=10.20.30.0/24
SEGMENTATION_LAN_GATEWAY=10.20.30.1
SEGMENTATION_MAC_ADDRESS=<MAC>
SEGMENTATION_LAN_IP=<IP>
SEGMENTATION_DHCP_HOSTNAME=<the hostname IT registered for the reservation>
SEGMENTATION_IMAGE=ghcr.io/jamesra/viking-segmentation-server:latest
```

- Only `segmentation-server` (the default model) starts. Further models are rows of
  `/srv/docker/Run/viking-segmentation/models.json`, added with `stack viking-segmentation model <prefix> <file.pt>`;
  see "More models" below.
- `SEGMENTATION_IMAGE` works with every Viking checkout. Viking checkouts newer than 2026-10-22 also
  accept the name `VIKING_SEGMENTATION_IMAGE`.
- Port settings copied from the old host (`SEGMENTATION_HTTPS_PORT`, ...) no longer apply: nothing is
  published on this host.
- If the copied file sets `SEGMENTATION_MODEL_HOST` or `SEGMENTATION_CACHE_DIR` to folders that don't
  exist here, change them (or remove them to use `/srv/docker/Data/viking-segmentation/models` and
  `.../cache`).

### 5c. Model weights

The weights and their `<stem>.model.json` manifests:

```bash
rsync -a deploy@compute:/srv/docker/Data/viking-segmentation/models/ \
    /srv/docker/Data/viking-segmentation/models/
```

The default server loads `SAM2_CHECKPOINT` (default `/models/best_TEM_model.pt`). Caches are rebuilt
on first use, so there is no need to copy them.

### 5d. Certificate

Copy the web host's certificate into this host's layout:

```bash
mkdir -p /srv/docker/Certs/connectomes.pitt.edu
scp -p deploy@web:/srv/docker/Certs/connectomes.pitt.edu/* /srv/docker/Certs/connectomes.pitt.edu/
```

The folder name is `TLS_CERT_NAME`, by default `VIKING_DOMAIN`. Renewals on `web` must reach this host
too. Add it to `targets.psd1` on the machine you deploy from, with `CertPush = $true`, and run
`stack.ps1 certs push -From web` after each renewal, as for the old compute host. `viking-certs`
(manual mode) on this host notices new files within 5 minutes and restarts the server.

## 6. Start and check

```bash
stack doctor
echo <token> | docker login ghcr.io -u <github-user> --password-stdin   # while the package is private
stack viking-certs up
stack viking-segmentation pull
stack viking-segmentation up
```

Then:

1. `stack viking-segmentation logs -Service segmentation-net` shows
   `DHCP bound: <IP> for <MAC>`. An `ERROR: DHCP offered ...` line means the reservation does not match;
   fix it with IT. The server keeps `<IP>` meanwhile.
2. `docker ps --format 'table {{.Names}}\t{{.Status}}'`: `segmentation-net` turns healthy once the
   lease is bound; `segmentation-server` can show `health: starting` for up to 10 minutes while it
   loads the weights.
3. IT's DHCP lease table shows `<MAC>` with `<IP>`.
4. From another machine (the new host itself can't reach the container's IP), e.g. on `web`:

   ```bash
   openssl s_client -connect <IP>:443 -servername segmentation.connectomes.pitt.edu </dev/null 2>/dev/null \
     | openssl x509 -noout -subject -enddate
   ```

   It prints the shared certificate.

## 7. Cut over

On `web`, in `/srv/docker/Run/viking-proxy/viking-proxy.run.env`, set:

```bash
VIKING_UPSTREAM_SEGMENTATION=<IP>:443
```

and restart the proxy:

```bash
stack viking-proxy restart
```

Run a segmentation from a Viking client. `stack viking-segmentation logs -Follow` on the new host shows
the request, and the old host's server goes quiet.

On `compute`, stop the old default server:

- **Segmentation leaves `compute` entirely:** run `stack viking-segmentation down` and remove
  `viking-segmentation` from `NORNIR_DOCKER_HOST_STACKS` in that host's `host.env`, so `stack all up`
  does not start it again. On the machine you deploy from, remove it from that target's `Stacks` in
  `targets.psd1`.
- **The v3 / v4 / sem-v1 models stay on `compute`:** stop only the default server with
  `docker stop viking-segmentation-segmentation-server-1`. A later `stack viking-segmentation up` or
  `restart` on `compute` starts it again, so stop it again after one. `viking-proxy` keeps sending the
  model hostnames to `VIKING_COMPUTE_HOST` as before.

## More models

Every other model is a row of `/srv/docker/Run/viking-segmentation/models.json` (the initializer copies an empty
table there). Put the weights and `<stem>.model.json` in `/srv/docker/Data/viking-segmentation/models/`, then:

```bash
stack viking-segmentation model v3 sam2_em_v3_epoch_9.pt   # add or change a server and start it
stack viking-segmentation model v5 v5/serve_epoch4.pt      # weights in a subfolder
stack viking-segmentation model -Remove v3                 # delete it
```

Each row becomes `<prefix>.segmentation.<domain>`. That has two labels, so `*.<domain>` does not cover it: ask for
`*.segmentation.<domain>` as an extra name on the certificate (with `<domain>` and `*.<domain>`) and install the issued
files with `stack certs manual`. In `letsencrypt` mode a wildcard cannot be validated, so each name is listed instead
(`viking-certs` leaves out a name that a wildcard already covers). How the proxy reaches a model is the row's `network`:

- `backend`: `viking-proxy` runs on this host and shares a Docker network with the server, so nothing is
  published. Set `VIKING_BACKEND_NETWORK=viking-backend` in `host.env` and add
  `stacks/viking-proxy/compose.backend.yaml` to the proxy's `STACK_COMPOSE_OVERLAYS`. This is the default
  once `VIKING_BACKEND_NETWORK` is set; use it whenever the proxy is on the same machine.
- `published`: host port `port`, reached as `SEGMENTATION_UPSTREAM_HOST:<port>` (default `VIKING_COMPUTE_HOST`).
  The default when the host has no backend network.
- `macvlan`: its own MAC and IP like the server above. The row sets `mac`, `ip` and `dhcpHostname`; the
  `SEGMENTATION_MACVLAN_PARENT` / `_LAN_SUBNET` / `_LAN_GATEWAY` settings are shared with the default server.

The command writes `Data/viking-segmentation/proxy-models.map` (host name and upstream per row) and
`cert-names.names` (the host names). Put them in `Data/viking-proxy/models.d/segmentation.map` and
`Data/viking-certs/names.d/segmentation.names` on the host that runs those stacks, or set
`SEGMENTATION_PROXY_MAP_DIR` and `SEGMENTATION_CERT_NAMES_DIR` to those folders when they are on this host.
Restart `viking-proxy` after the map changes. TLS can also come from your own files:
`SEGMENTATION_CERT_DIR=<folder with fullchain.pem and privkey.pem>`.
Viking's `Documentation/source/deployment/segmentation.rst` lists every row field.

## Rollback

1. On `web`, remove `VIKING_UPSTREAM_SEGMENTATION` from the proxy run env and run
   `stack viking-proxy restart`.
2. On `compute`, run `stack viking-segmentation up`.

## Running it day to day

- **New image:** run `stack viking-segmentation pull`, then `stack viking-segmentation up`. Don't use
  `rebuild`: it builds on the host.
- **Restarting:** `segmentation-server` uses `segmentation-net`'s network. Restart both together with
  `stack viking-segmentation restart`, never `segmentation-net` alone.
- **Firewall:** traffic to `<IP>` bypasses the host firewall (ufw and the `DOCKER-USER` chain). Only
  network ACLs filter it.
- **Certificate expiry:** `stack certs status` on the new host shows the certificate's expiry date.
- **Background:** `stacks/viking-segmentation/compose.macvlan.yaml` and Viking's
  `Documentation/source/deployment/segmentation.rst` ("Own MAC address and IP").
