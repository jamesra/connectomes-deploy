---
name: operate-build-host
description: Day-to-day operation of a running nornir build host (opr-marc-build2 / srv) - after a host reboot, after a NAS IP or SMB-encryption change, after a nornir image install, and the checks that keep getting re-derived. Use when a build host's containers, NAS mounts or agent addresses misbehave after a change. For first-time setup use deploy-compute-host.
---

# Operate a running build host

Each rule: what to do, then why.

## After a host reboot
- `stack nornir-dashboard up`, then `stack nornir-build up`. nornir-build does not auto-start, and it joins the
  dashboard's network for MQTT, so the dashboard must be up first.
- Run `ListAgents` again before messaging anyone. Local session addresses (uds sockets) change on reboot; old ones fail.
- Tell every job owner the container restarted; their in-flight runs died and they resume them.

## NAS address change (e.g. storage3 .236 -> .233)
- Change both places: `Run/nornir-net-mounts/net-mounts/nas-mounts.tsv` (container) and `/etc/fstab` (host; the
  user runs `sudo mount <path>` and `sudo systemctl daemon-reload`). They are separate copies.
- The tsv is read only at container start: rebuild nornir-build at an idle point. If a share comes up empty or
  offline right after the rebuild, re-list once, then rebuild once more before debugging.
- Check reachability first: `timeout 4 bash -c '</dev/tcp/<ip>/445' && echo open`. Workstation-side private
  addresses (192.168.x) are not routable from build hosts; copies or block clones between such a share and a build
  host's shares cannot be done from the build host.

## SMB encryption
- `seal` in mount options must match the NAS: with encryption off on the NAS, `seal` fails with `error 95`
  (EOPNOTSUPP). Remove it from that row.
- After any encryption or firewall change, test a large read (>1 GB, `dd ... status=progress`), not a listing:
  campus packet inspection has dropped large unencrypted SMB reads while small ones worked.
- CIFS metadata is slow: glob known paths; never `find` across a whole volume.

## After a nornir image install
- The container gets a new `/workspace` (`Work/nornir-build-<ver>-<stamp>`). Move the old folder's contents
  forward with a root container (`docker run --rm --entrypoint mv -v /srv/docker/Work:/w nornir:cupy ...`),
  then `rmdir` the old one: files written by the container are root-owned, and the deploy user can't move them.

## Segmentation server
- It runs as uid 1001. Set `TLS_KEY_GID=1001` in host.env so `privkey.pem` is group-readable (0640); otherwise TLS
  startup fails with a permission error on the key.

## Agent shells
- `docker exec <container> bash -c '...'`, never `stack exec` (forces `-it`) or `bash -lc` (a login shell resets
  PATH and loses `/root/scripts`, `/opt/venv/bin`).
- `tail -n 1` and `head -n N`, not `tail -1`: coreutils on srv is uutils, which rejects the obsolete form.
- Never `pkill -f <pattern>` from a shell whose command line contains the pattern: it kills that shell (exit 143/144).
  Kill by PID, or bracket one letter (`pgrep -f 'resource_trac[k]er'`).
- Yes/no checks use `grep -q`; `$(... | grep -c x || echo 0)` yields "0\n0" on no match.
