# Stack registry for connectomes-deploy (read by stack.ps1).
# Source-repo registries with the same schema are added by STACK_EXTRA_REGISTRIES in host.env
# (default: <Viking>/deploy/stacks.psd1 and <nornir>/nornir-docker/dev-stacks.psd1).
#
# Engine:
#   compose - stack.ps1 runs docker compose -p <key> --env-file ... -f <ComposeFiles> <action>
#   script  - stack.ps1 calls an existing launcher (Script) with ActionArgs per action; observation
#             actions (logs/ps/exec/shell/down) use Container (docker run stacks) or
#             ComposeProject+ComposeFiles (compose-managed by the launcher).
#   iis     - Windows IIS deployment script (Viking only).
#
# Paths (forward slashes):
#   Example, SecretExamples  relative to this repo
#   Script, ComposeFiles, Deploy  relative to the RepoRootVar checkout (default: this repo).
#     The nornir stacks still run from the nornir checkout until their images are published.
@{
    Stacks = @{
        'nornir-build' = @{
            Engine      = 'script'
            Description = 'Production build appliance: nornir:cupy (GPU) or nornir:prod, path-B CIFS, per-session Work folder'
            RepoRootVar = 'NORNIR_REPO_ROOT_HOST'
            Script      = 'nornir-docker/start-nornir-build.ps1'
            Container   = 'nornir-build'
            ActionArgs  = @{
                up    = @('-Detach', '-KeepContainer', '-ContainerName', 'nornir-build')
                shell = @()
            }
            Example     = 'stacks/nornir-build/example.nornir-build.run.env'
            Required    = @()
            Secrets     = @()
            Images      = @('nornir:cupy', 'nornir:prod')
            Ports       = @()
            Os          = @('linux', 'windows')
        }
        'nornir-dashboard' = @{
            Engine         = 'script'
            Description    = 'Mosquitto broker + nornir build dashboard (http://<NORNIR_DASHBOARD_BIND_HOST>:<NORNIR_DASHBOARD_HOST_PORT>, default 127.0.0.1:80)'
            RepoRootVar    = 'NORNIR_REPO_ROOT_HOST'
            Script         = 'nornir-docker/start-dashboard.ps1'
            ComposeProject = 'nornir-dashboard'
            ComposeFiles   = @('nornir-docker/compose.dashboard.yaml')
            DefaultService = 'nornir-dashboard'
            ActionArgs     = @{
                up      = @()
                restart = @()
                rebuild = @('-Rebuild')
                down    = @('-Down')
            }
            Example        = 'stacks/nornir-dashboard/example.nornir-dashboard.run.env'
            Required       = @()
            GeneratedSecrets = @('NORNIR_DASHBOARD_TOKEN')
            Secrets        = @()
            HealthUrl      = 'http://{NORNIR_DASHBOARD_BIND_HOST}:{NORNIR_DASHBOARD_HOST_PORT}/'
            Images         = @('nornir-dashboard:latest', 'eclipse-mosquitto:2')
            Ports          = @(1883, 80)
            Os             = @('linux', 'windows')
        }
    }
}
