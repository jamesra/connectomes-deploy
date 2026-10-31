# connectomes-deploy

Goal: simplify and harmonise the deployment of **all server-side resources** of the connectomes backend (nornir
build appliance and dashboard, Viking identity / annotation / corrections / segmentation servers, proxy,
certificates, IIS), in whole or in part, through one entry point (`stack.ps1`) and one host layout.

Read before editing:

- [README.md](README.md): layout and quick start.
- [docs/conventions.md](docs/conventions.md): the goal in detail and the conventions to keep (registries, settings
  and secrets layers, opt-in overlays, image pins, rollout procedure, scripts, docs, commit messages).
- [docs/segmentation-host.md](docs/segmentation-host.md): worked example of a guide.
- Operator procedure: nornir `deploy-connectomes` skill (`D:\src\git\nornir\.cursor\skills\deploy-connectomes`).
- Bringing up a NEW compute host from scratch (nornir-build, segmentation, certificates), with the mistakes that cost
  time: skill `deploy-compute-host` ([.cursor/skills/deploy-compute-host/SKILL.md](.cursor/skills/deploy-compute-host/SKILL.md)).
  It ends by notifying the host's bot (for opr-marc-build2, the `Build2 RC` session) when one is available.

Essentials:

- Service definitions (Dockerfiles, compose files, their registries) stay in the Viking and nornir checkouts; this
  repo holds the tooling, shared registry, templates, image pins and guides. No application code here.
- No secrets in git, `host.env` or run envs. Templates are `example.*` with `REQUIRED`/`OPTIONAL` comments.
- New optional behaviour is opt-in; with it unset, every existing stack's rendered compose config stays identical.
- Commits say what was checked. Work on the branch the checkout is on; push only when asked. Live hosts pull from
  pushed commits via `-Sync`, so never edit files on a server.
- Deploys act on live hosts: confirm the target and run `doctor` first; ask before `down`, `rebuild` or certificate
  changes on a production host unless told to proceed.
