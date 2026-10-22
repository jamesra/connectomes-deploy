# connectomes-deploy

One place to install and run the connectomes backend (nornir build appliance and dashboard,
Viking identity / annotation / corrections / segmentation servers, proxy and certificates) on
Ubuntu or Windows Docker hosts.

`stack.ps1` is the single entry point for every stack, locally or on a remote host with
`-Target <name>` over SSH.

## Quick start (Ubuntu)

```bash
curl -fsSL https://raw.githubusercontent.com/jamesra/connectomes-deploy/main/bootstrap-ubuntu.sh -o bootstrap-ubuntu.sh
sudo bash bootstrap-ubuntu.sh --user deploy [--gpu] [--open-web]
```

Then follow the commands it prints: clone this repo to `/srv/connectomes-deploy`, run
`Initialize-DockerHost.ps1 -Role compute|web`, edit `Run/_host/host.env` and each
`Run/<stack>/<stack>.run.env`, then:

```bash
stack doctor
stack all up
```

## Layout

| Path | What |
|------|------|
| `stack.ps1` | Entry point: `list`, `doctor`, `certs`, `secrets`, `tunnel`, `prune`, `targets`, and `<stack> up/down/rebuild/logs/...` |
| `Initialize-DockerHost.ps1` | One-time host layout setup (`Run/`, `Data/`, `Certs/`, `Work/`, `Logs/` under `NORNIR_DOCKER_USER_ROOT`) |
| `Move-DockerHostLayout.ps1` | Migrates the older `D:\Docker` layout |
| `bootstrap-ubuntu.sh` | Ubuntu prerequisites: Docker, PowerShell 7, NVIDIA container toolkit, ufw, sshd |
| `stacks.psd1` | Stack registry |
| `stacks/<stack>/` | Per-stack templates (`example.<stack>.run.env`, ...) |
| `host/` | Host templates: `host.env`, host secrets, remote `targets.psd1` |
| `lib/` | Shared PowerShell helpers |

Some stacks still run from source checkouts (`NORNIR_REPO_ROOT_HOST`, `VIKING_REPO_ROOT_HOST` in
`host.env`) until their images are published; their registries are loaded through
`STACK_EXTRA_REGISTRIES`.

## Docs

- [New segmentation host on its own MAC and IP](docs/segmentation-host.md): step by step, including
  the DHCP reservation and the cut-over from the old compute host.
- Deployment guide (all hosts): https://nornir.github.io/deployment/. It still describes the older
  `nornir-docker/deploy` layout; use this repo's scripts in its place.
