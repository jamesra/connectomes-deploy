---
name: operate-web-host
description: Operate the running web host HypV1 (viking-proxy, viking-certs behind the Pitt load balancer) - check whether IT switched the load balancer to passthrough, test proxied names from the host, keep key permissions, renew CertiNext certificates, clean root-owned files, and apply image updates. Use for any change, check or cleanup on HypV1 or the public proxy for connectomes.pitt.edu.
---

# Operate the web host (HypV1)

Written by the HypV1 host session from its own history (2026-11-21). HypV1 cannot push: repo changes go to the
dispatcher or the dev box for commit. On the host, only fast-forward pulls and edits to `host.env` and `Run/` files.

## Pitt load balancer (re-derived three times)

- 10.250.242.7 and .8 terminate TLS with their own SSL.com certificate (SHA-256 `BD:B0:45…F2:5C`), then re-encrypt to
  10.227.66.253:443 **without SNI, HTTP/1.1 only**.
- Keep `VIKING_UPSTREAM_DEFAULT=127.0.0.1:8444`; without it every load-balancer connection is refused.
- Has IT switched to passthrough? Compare
  `openssl s_client -connect connectomes.pitt.edu:443 -servername connectomes.pitt.edu -alpn h2 | openssl x509 -noout -fingerprint -sha256`
  with `Certs/<name>/fullchain.pem`. Passthrough shows our certificate and ALPN h2.

## Testing proxied names from the host

- The host cannot reach its own macvlan IPs. Test from inside the proxy (its image has curl):
  `docker exec viking-proxy-viking-proxy-1 curl -s -o /dev/null -w '%{http_code}' --resolve <name>:443:10.227.66.253 https://<name>/`
- Upstream directly: `curl -k https://10.227.66.252/`.
- A check from inside campus does not prove off-campus access. Check public DNS with `dig @8.8.8.8 <name>`; a public
  record pointing at a private address (10.x, 172.16-31.x, 192.168.x) is unreachable off campus. Say which vantage
  point each check ran from.

## Certificates and keys

- viking-proxy's nginx workers (uid/gid 101) read `privkey.pem` on every handshake (the cert paths are variables).
  Keep `TLS_KEY_GID=101` in `host.env` so the renewer publishes `root:101 0640`. Never set `root:root 0600` on
  `privkey.pem` (that broke HTTPS on 2026-11-20).
- CertiNext `acme-eab` issues without an HTTP-01 challenge (the domain is pre-validated), so port 80 is not needed.
- Only James enters EAB secrets, into `Run/viking-certs/secrets/`; never in chat or git.
- `renew-loop.sh` is baked into the image: after changing it, `stack viking-certs rebuild`.

## Image updates and security patches

- After pulling a floating tag (`nginx:stable`, `:latest`), `stack <s> up` can leave the container running on the old
  image. Use `stack <s> restart` (force-recreates), then confirm with `docker inspect <c> --format '{{.Image}}'`.
- Don't run raw `docker compose` for stack-managed services: `stack.ps1` exports `STACK_DATA_DIR`,
  `DOCKER_CERTS_DIR` and other required variables.
- Before restarting for a security patch, read the vendor advisory ("Not vulnerable" column; nginx:
  https://nginx.org/en/security_advisories.html) and compare with `docker exec <c> nginx -v`. A new image ID on the
  same tag may carry identical packages: `docker run --rm --entrypoint sh <img> -c 'dpkg-query -W nginx openssl'`.
  Report whether the restart actually changed the version.
- `docker run --rm <image:tag>` pulls tags you don't have: remove images pulled only to compare (`docker rmi`) and
  prune dangling images after a recreate.

## Root-owned files under /srv/docker

- Delete them with a throwaway root container: `docker run --rm -v <dir>:/d alpine rm /d/<file>`, not sudo.
- certbot rotates its logs (`Logs/viking-certs`): check contents and numbering before deleting; delete only what you
  made or verified is the target.
