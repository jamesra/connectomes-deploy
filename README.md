# connectomes-deploy

One place to install and run the connectomes backend (nornir build appliance and dashboard,
Viking identity / annotation / corrections / segmentation servers, proxy and certificates) on
Ubuntu or Windows Docker hosts.

`stack.ps1` is the single entry point for every stack, locally or on a remote host with
`-Target <name>` over SSH.

## Quick start (Ubuntu)

Run these from the account you will deploy as (any login that can sudo):

```bash
curl -fsSL https://raw.githubusercontent.com/jamesra/connectomes-deploy/main/bootstrap-ubuntu.sh -o bootstrap-ubuntu.sh
sudo bash bootstrap-ubuntu.sh [--gpu] [--open-web]
```

That account becomes the deploy user. For a dedicated account instead, create it first
(`sudo adduser deploy`) and add `--user deploy`. Then follow the commands it prints: clone this repo to `/srv/connectomes-deploy`, run
`Initialize-DockerHost.ps1 -Role compute|web`, edit `Run/_host/host.env` and each
`Run/<stack>/<stack>.run.env`, then:

```bash
stack doctor
stack all up
```

## Commands on your PATH

`scripts/` holds thin wrappers so you can run the tooling from any folder. Each command is a PowerShell script
(`<name>.ps1`) and a bash twin (`<name>.sh`) that only calls it:

| Command | Runs |
|---------|------|
| `stack` | `stack.ps1` of this checkout (`stack doctor`, `stack viking-segmentation up`, ...) |
| `initialize-dockerhost` | `Initialize-DockerHost.ps1` |
| `segmentation-model` | `stack.ps1 viking-segmentation model` (`segmentation-model v5 v5/serve_epoch4.pt`) |

Ubuntu: `echo 'export PATH="$PATH:/srv/connectomes-deploy/scripts"' >> ~/.profile`, then `stack.sh doctor`. For the plain
names, link them: `ln -s /srv/connectomes-deploy/scripts/stack.sh ~/bin/stack` (the `.sh` files are executable and
follow symlinks). Windows: add `D:\src\git\connectomes-deploy\scripts` to `PATH`; PowerShell then runs `stack` and
`segmentation-model` directly. `Initialize-DockerHost.ps1` also adds a `stack` alias for you with `-SetUserEnv`.

## Layout

| Path | What |
|------|------|
| `scripts/` | Commands for your `PATH`: `stack`, `initialize-dockerhost`, `segmentation-model`, each a `.ps1` with a `.sh` twin that calls it (see "Commands on your PATH") |
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

- [Goal and conventions](docs/conventions.md): what this repo is for and the conventions to keep when adding
  stacks, settings, images or guides.
- [New segmentation host on its own MAC and IP](docs/segmentation-host.md): step by step, including
  the DHCP reservation and the cut-over from the old compute host.
- Deployment guide (all hosts): https://nornir.github.io/deployment/. It still describes the older
  `nornir-docker/deploy` layout; use this repo's scripts in its place.
