# Goal and conventions

## Goal

connectomes-deploy exists to **simplify and harmonise the deployment of every server-side resource** of the
connectomes backend, in whole or in part: the nornir build appliance and dashboard, the Viking identity, annotation,
corrections and segmentation servers, the reverse proxy, certificates, and the Windows IIS host. One command shape,
one host layout and one set of settings files cover every service, so a single stack, a single host or the whole
backend is deployed the same way, locally or on a remote target.

What "harmonious" means here:

- **One entry point.** `stack.ps1 <stack> <action>` for every stack, whatever it runs underneath (compose, a legacy
  launcher script, or the IIS deploy script). Local and remote commands differ only by `-Target <name>`.
- **Whole or part.** `stack.ps1 all <action>` acts on the stacks a host lists in `NORNIR_DOCKER_HOST_STACKS`; any
  stack can be run alone; a host can run a subset (the segmentation host runs only `viking-segmentation`).
- **One host layout** under `NORNIR_DOCKER_USER_ROOT` (`D:\Docker` on Windows, `/srv/docker` on Ubuntu), created by
  `Initialize-DockerHost.ps1`: `Run/`, `Data/`, `Certs/`, `Work/`, `Logs/`.
- **Deploy tooling lives here; service definitions stay with the service.** Compose files, Dockerfiles and each
  source repo's own stack registry stay in the Viking and nornir checkouts and are pulled in through
  `STACK_EXTRA_REGISTRIES`. This repo holds the cross-cutting parts: the entry point, shared registry, host and
  stack templates, host bootstrap, certificates, image pins and the guides. It does not contain application code.

## Conventions used so far

Keep new work consistent with these; they are what the existing scripts and docs already do.

### Stacks and the registry

- A stack is one key in a `stacks.psd1` registry (`Engine` = `compose`, `script` or `iis`). Names are lower-case,
  hyphenated and prefixed by the product: `nornir-*`, `viking-*`.
- Registry fields are the same in this repo's `stacks.psd1` and the source repos' registries (`Description`,
  `Example`, `Required`, `Secrets`, `GeneratedSecrets`, `HealthUrl`, `Images`, `Ports`, `Os`, plus the engine's own
  fields). Fill in all of them for a new stack, even when empty (`Ports = @()`), so `doctor` can check everything.
- Paths in registries use forward slashes. `Example` and `SecretExamples` are relative to this repo; `Script`,
  `ComposeFiles` and `Deploy` are relative to the checkout named by `RepoRootVar`.
- Optional registry fields: `ModelScript` (a script in the stack's checkout that `stack.ps1 <stack> model ...`
  runs; it updates `Run/<stack>/models.json`, writes `compose.generated.yaml`, which is merged after the overlays,
  and reports the services to start in `STACK_ACTION_RESULT`), `ModelsExample` (the table's template, copied by
  `Initialize-DockerHost.ps1`) and `DataDirs` (folders under `Data/<stack>/` that other stacks write into, created
  before the stack mounts them).
- A registry is authoritative for what a stack needs. If a stack needs a new setting, add it to `Required` and to
  the template; do not make `stack.ps1` special-case the stack.
- An unknown stack must fail with the registries read, the ones skipped and why, and the fix (see the "not in any
  registry" message). Error messages explain the cause and the remedy, not just the symptom.

### Settings and secrets

- **Three layers, all outside git:** `Run/_host/host.env` (machine-wide), `Run/<stack>/<stack>.run.env` (per stack),
  and `secrets/secrets.env` files (machine-wide in `Run/_host/secrets/`, per stack in `Run/<stack>/secrets/`).
  Templates for each live in this repo as `example.*` files (`host/`, `stacks/<stack>/`).
- Secrets never go in `host.env` or a run env, and never in git. `stack.ps1 secrets new <stack>` fills generated
  secrets; it never invents `SQL_SERVER_PASSWORD` or connection strings.
- Every key in a template is commented with `REQUIRED` or `OPTIONAL`, what it does, and its default. Optional keys
  are shipped commented out (`#KEY=default`). Keep that style.
- A setting used by several stacks belongs in `host.env` (shared names, identity URLs, shared folders); a setting
  used by one stack belongs in that stack's run env. Derive shared values once (for example `VIKING_IDENTITY_URL`
  from `VIKING_HOSTNAME_IDENTITY`) and export them to every stack. A stack's own explicit setting wins over the
  shared default.
- Public hostnames are single-label subdomains of `VIKING_DOMAIN`, so one `*.domain` wildcard certificate covers
  every service. The exception is the
  segmentation model servers, `<prefix>.segmentation.<domain>`, which need `*.segmentation.<domain>` on the
  certificate (or each name listed).
- `stack.ps1 <stack> build` must not require run-time settings or secrets, so a dev box can build images from a
  clean checkout.

### Optional behaviour is opt-in

- Extra behaviour is a separate file or key that is off by default, not a change to the base stack: for example
  `STACK_COMPOSE_OVERLAYS` (extra compose files merged after the registry's, such as `compose.macvlan.yaml`) and
  `STACK_PROFILES` (replaces the registry's default profiles; `none` turns them off).
- With the new keys unset, the rendered `docker compose config` of every existing stack must be unchanged. Verify
  that when adding an overlay or key.
- Linux-only features (macvlan) say so in the file and the guide; `Os` in the registry says which hosts a stack
  runs on.

### Images and releases

- Images carry their source: `STACK_SOURCE_REVISION` (HEAD commit, suffixed `-dirty` when tracked files are
  modified) is passed to builds as `SOURCE_REVISION`, so images get `org.opencontainers.image.revision`. Publishing
  refuses images without a clean revision.
- Third-party and published images are pinned in `release/images.psd1` (Repository + Tag chosen by hand; Digest,
  Source, Revision and Created filled by `release/Update-ImageLock.ps1`, which `-Check` verifies). It is the
  deploy-side equivalent of submodule pointers. Add every image a stack runs to it, with the stacks that use it.
- A target obtains images by `-Images build` (default, built on the target), `ghcr` (pulled) or `load`
  (`docker save | ssh docker load`). The Viking segmentation image is published to and pulled from GHCR.

### Rolling out a change

1. `stack.ps1 doctor -Target <host>`; fix every `[FAIL]` first.
2. Push the commits to deploy (submodule commits first, then the umbrella pointer).
3. `stack.ps1 <stack> rebuild -Target <host> -Sync` (`up` when the image is unchanged). `-Sync` refuses unpushed
   local branches and does `git pull --ff-only` on the target.
4. `stack.ps1 <stack> status -Target <host>`, then `logs` if anything looks wrong.

Never edit files on a server to work around `-Sync`. The nornir `deploy-connectomes` skill is the operator procedure
(hosts, certificates, secrets, debugging); this repo holds the tooling it drives.

### Scripts

- PowerShell 7.2+ (`#Requires -Version 7.2`), with comment-based help (`.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`,
  `.EXAMPLE`) on every entry-point script, and cross-platform: the same script runs on Windows and Ubuntu.
  `bootstrap-ubuntu.sh` is the only shell prerequisite; it documents its own flags in its header and `--help`.
- A command you run often gets a wrapper in `scripts/`: `<name>.ps1` calls the entry point and `<name>.sh` only calls
  `<name>.ps1`, so one folder on `PATH` serves both shells (keep the `.sh` files executable).
- Shared helpers go in `lib/`; entry points stay thin. `stack.ps1 <stack> <action>` and `stack.ps1 <action> <stack>`
  are both accepted.
- Use forward slashes in registry paths and `Join-Path` in code. Do not hard-code an account named `deploy`; the
  deploy user is whichever account ran the bootstrap (or `--user`).

### Documentation and commits

- Guides are step by step and name the exact commands (`docs/segmentation-host.md` is the model), say what to check
  after each step, and give a rollback. Update the README layout table and Docs list when adding a file or guide.
- The deployment guide at https://nornir.github.io/deployment/ is nornir `docs/deployment/`. It describes this repo
  from nornir `dev` on (published when nornir `master` is updated); `nornir-docker/deploy` is the superseded copy.
  When behaviour here changes, update those pages and any guide that still describes the old way.
- Commit messages: a short imperative subject naming the feature, then a body that says what changed and **what was
  checked and how** (which hosts or scratch layouts, which cases). Commit finished work at once; push only when
  asked.
- Record citations, formulas and design decisions with their reasons in `docs/publication_notes.md`
  (`publication-notes` skill).
