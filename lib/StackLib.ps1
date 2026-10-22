<#
.SYNOPSIS
  Shared helpers for stack.ps1: host layout, stack registries, env merging, compose/ssh invocation.

.DESCRIPTION
  Dot-sourced by stack.ps1, Initialize-DockerHost.ps1, and Move-DockerHostLayout.ps1. Written for
  PowerShell 7 on Windows and Ubuntu: paths are built with Join-Path segments (never literal
  backslashes) and OS-specific behaviour branches on Test-NornirWindowsHost.

  Host layout (root = NORNIR_DOCKER_USER_ROOT; D:\Docker on Windows, /srv/docker on Linux):
    Run/_host/host.env, Run/_host/targets.psd1, Run/<stack>/<stack>.run.env, Run/<stack>/secrets/,
    Builds/<stack>/, Data/<stack>/, Certs/<cert-name>/, Work/, Logs/<stack>/
#>

. (Join-Path $PSScriptRoot 'DotEnv.ps1')

# This file lives in <connectomes-deploy>/lib.
$script:DeployRepoRoot = Split-Path -Parent $PSScriptRoot

# Source-repo registries loaded when STACK_EXTRA_REGISTRIES is not set in host.env.
# Entries are <RepoRootVar>:<registry path relative to that repo>; missing files are skipped.
$script:DefaultExtraRegistries = @(
    'VIKING_REPO_ROOT_HOST:deploy/stacks.psd1',
    'NORNIR_REPO_ROOT_HOST:nornir-docker/dev-stacks.psd1'
)

function Test-NornirWindowsHost {
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Get-DockerHostRoot {
    <#
    .SYNOPSIS
      Resolve the machine-local Docker root (NORNIR_DOCKER_USER_ROOT; D:\Docker or /srv/docker).
    #>
    param([string]$Root = '')
    if (-not [string]::IsNullOrWhiteSpace($Root)) { return $Root.Trim() }
    if ($env:NORNIR_DOCKER_USER_ROOT -and $env:NORNIR_DOCKER_USER_ROOT.Trim()) {
        return $env:NORNIR_DOCKER_USER_ROOT.Trim()
    }
    if (Test-NornirWindowsHost) { return 'D:\Docker' }
    return '/srv/docker'
}

function Join-DockerHostPath {
    <#
    .SYNOPSIS
      Join a root with any number of path segments using the platform separator.
    #>
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(ValueFromRemainingArguments)][string[]]$Segments
    )
    $p = $Root
    foreach ($s in $Segments) {
        foreach ($part in ($s -split '[\\/]')) {
            if ($part) { $p = Join-Path $p $part }
        }
    }
    return $p
}

function ConvertTo-DockerBindPath {
    <#
    .SYNOPSIS
      Forward-slash form of a host path for compose interpolation (Docker Desktop accepts D:/x).
    #>
    param([Parameter(Mandatory)][string]$Path)
    return ($Path -replace '\\', '/')
}

function Get-DockerHostLayout {
    param([string]$Root = '')
    $r = Get-DockerHostRoot -Root $Root
    return [ordered]@{
        Root     = $r
        HostDir  = Join-DockerHostPath $r 'Run' '_host'
        HostEnv  = Join-DockerHostPath $r 'Run' '_host' 'host.env'
        HostSecretsEnv = Join-DockerHostPath $r 'Run' '_host' 'secrets' 'secrets.env'
        Targets  = Join-DockerHostPath $r 'Run' '_host' 'targets.psd1'
        Run      = Join-DockerHostPath $r 'Run'
        Builds   = Join-DockerHostPath $r 'Builds'
        Data     = Join-DockerHostPath $r 'Data'
        Certs    = Join-DockerHostPath $r 'Certs'
        Work     = Join-DockerHostPath $r 'Work'
        Logs     = Join-DockerHostPath $r 'Logs'
    }
}

function Get-StackDirs {
    param(
        [Parameter(Mandatory)][string]$Stack,
        [string]$Root = ''
    )
    $l = Get-DockerHostLayout -Root $Root
    $run = Join-DockerHostPath $l.Run $Stack
    return [ordered]@{
        Run        = $run
        RunEnv     = Join-DockerHostPath $run "$Stack.run.env"
        Secrets    = Join-DockerHostPath $run 'secrets'
        SecretsEnv = Join-DockerHostPath $run 'secrets' 'secrets.env'
        Data       = Join-DockerHostPath $l.Data $Stack
        Logs       = Join-DockerHostPath $l.Logs $Stack
        Builds     = Join-DockerHostPath $l.Builds $Stack
    }
}

function Read-HostEnv {
    <#
    .SYNOPSIS
      Merge Run/_host/host.env and Run/_host/secrets/secrets.env (later wins) into a hashtable.
    #>
    param([string]$Root = '')
    $l = Get-DockerHostLayout -Root $Root
    $merged = @{}
    foreach ($p in @($l.HostEnv, $l.HostSecretsEnv)) {
        foreach ($e in (Read-NornirDotEnvFile $p).GetEnumerator()) { $merged[$e.Key] = $e.Value }
    }
    return $merged
}

function Get-RepoRootFromEnv {
    <#
    .SYNOPSIS
      Resolve a repo root from process env, then host.env, with legacy fallbacks.

    .DESCRIPTION
      DEPLOY_REPO_ROOT_HOST falls back to this checkout. Source repos (NORNIR_REPO_ROOT_HOST,
      VIKING_REPO_ROOT_HOST) have no fallback: a host without that checkout returns $null.
    #>
    param(
        [Parameter(Mandatory)][string]$VarName,
        [hashtable]$HostEnv = @{}
    )
    $legacy = @{
        'NORNIR_REPO_ROOT_HOST' = @('NORNIR_MONOREPO_ROOT')
    }
    $names = @($VarName) + @($legacy[$VarName] | Where-Object { $_ })
    foreach ($n in $names) {
        $v = [Environment]::GetEnvironmentVariable($n)
        if ([string]::IsNullOrWhiteSpace($v) -and $HostEnv.ContainsKey($n)) { $v = $HostEnv[$n] }
        if (-not [string]::IsNullOrWhiteSpace($v)) {
            if ($n -ne $VarName) { Write-Warning "$n is deprecated for the host repo path; set $VarName in host.env." }
            return $v.Trim()
        }
    }
    if ($VarName -eq 'DEPLOY_REPO_ROOT_HOST') { return $script:DeployRepoRoot }
    return $null
}

function Get-StackRegistrySources {
    <#
    .SYNOPSIS
      The registry files to load: this repo's stacks.psd1, then STACK_EXTRA_REGISTRIES (or the defaults).

    .DESCRIPTION
      STACK_EXTRA_REGISTRIES is a comma list of <RepoRootVar>:<path relative to that repo>, e.g.
      VIKING_REPO_ROOT_HOST:deploy/stacks.psd1. Set it to `none` to load only this repo's registry.
    #>
    param([hashtable]$HostEnv = @{})
    $sources = [System.Collections.Generic.List[hashtable]]::new()
    $sources.Add(@{ Var = 'DEPLOY_REPO_ROOT_HOST'; Rel = 'stacks.psd1' })
    $raw = $HostEnv['STACK_EXTRA_REGISTRIES']
    $extra = if ([string]::IsNullOrWhiteSpace($raw)) { $script:DefaultExtraRegistries }
    elseif ($raw.Trim() -eq 'none') { @() }
    else { @($raw -split '[,\s]+' | Where-Object { $_ }) }
    foreach ($x in $extra) {
        $var, $rel = $x -split ':', 2
        if (-not $rel) { Write-Warning "STACK_EXTRA_REGISTRIES entry '$x' is not <RepoRootVar>:<path>; skipped"; continue }
        $sources.Add(@{ Var = $var.Trim(); Rel = $rel.Trim() })
    }
    return , $sources.ToArray()
}

function Import-StackRegistry {
    <#
    .SYNOPSIS
      Load this repo's stacks.psd1 plus the source-repo registries named by STACK_EXTRA_REGISTRIES.

    .DESCRIPTION
      Each entry gains:
        RegistryRoot  repo that holds the registry file; Example / SecretExamples resolve here
        RepoRootVar   repo the entry's Script / ComposeFiles / Deploy live in (default: the registry's repo)
        RepoRoot      that repo's path on this host, or $null when the variable is not set
        RegistryPath  the registry file

    .OUTPUTS
      Ordered hashtable stack-key -> entry.
    #>
    param([hashtable]$HostEnv = @{})
    $out = [ordered]@{}
    $report = [System.Collections.Generic.List[object]]::new()
    foreach ($src in (Get-StackRegistrySources -HostEnv $HostEnv)) {
        $registryRoot = Get-RepoRootFromEnv -VarName $src.Var -HostEnv $HostEnv
        $item = [ordered]@{ Var = $src.Var; Rel = $src.Rel; Root = $registryRoot; Path = ''; Status = 'unset'; Stacks = @() }
        $report.Add($item)
        if (-not $registryRoot) { continue }
        $path = Join-DockerHostPath $registryRoot $src.Rel
        $item.Path = $path
        if (-not (Test-Path -LiteralPath $path)) { $item.Status = 'missing'; continue }
        $data = Import-PowerShellDataFile -LiteralPath $path
        $item.Status = 'loaded'
        $item.Stacks = @($data.Stacks.Keys | Sort-Object)
        foreach ($k in ($data.Stacks.Keys | Sort-Object)) {
            $entry = @{} + $data.Stacks[$k]
            $entry.Key = $k
            $entry.RegistryRoot = $registryRoot
            $entry.RepoRootVar = if ($entry.RepoRootVar) { $entry.RepoRootVar } else { $src.Var }
            $entry.RepoRoot = if ($entry.RepoRootVar -eq $src.Var) { $registryRoot } else { Get-RepoRootFromEnv -VarName $entry.RepoRootVar -HostEnv $HostEnv }
            $entry.RegistryPath = $path
            if ($out.Contains($k)) { Write-Warning "Stack '$k' in $path replaces the one in $($out[$k].RegistryPath)" }
            $out[$k] = $entry
        }
    }
    $script:RegistryReport = $report.ToArray()
    return $out
}

function Get-StackRegistryHelp {
    <#
    .SYNOPSIS
      Explain an unknown stack name: which registry files were read, which were not, and how to fix it.

    .DESCRIPTION
      Uses what the last Import-StackRegistry saw. Viking stacks come from <VIKING_REPO_ROOT_HOST>/deploy/
      stacks.psd1, which exists on Viking's dev branch, so a missing or unset Viking checkout is the
      usual cause.
    #>
    param([string]$Key = '')
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("Stack registries read (host.env decides where they are):")
    foreach ($r in @($script:RegistryReport)) {
        switch ($r.Status) {
            'loaded' { $lines.Add("  ok       $($r.Path): $(@($r.Stacks) -join ', ')") }
            'unset' { $lines.Add("  not read $($r.Var) is not set in host.env, so $($r.Var)/$($r.Rel) was skipped.") }
            'missing' { $lines.Add("  not read $($r.Path) does not exist ($($r.Var)=$($r.Root)).") }
        }
    }
    $viking = @($script:RegistryReport) | Where-Object { $_.Var -eq 'VIKING_REPO_ROOT_HOST' } | Select-Object -First 1
    if ($Key -like 'viking-*' -and $viking -and $viking.Status -ne 'loaded') {
        $lines.Add("'$Key' is a Viking stack, defined in the Viking checkout's deploy/stacks.psd1 (branch dev). Fix:")
        if ($viking.Status -eq 'unset') {
            $lines.Add("  git clone -b dev https://github.com/jamesra/Viking.git /srv/src/Viking   (if you have no checkout)")
            $lines.Add("  set VIKING_REPO_ROOT_HOST=/srv/src/Viking in Run/_host/host.env")
        }
        elseif (-not (Test-Path -LiteralPath $viking.Root)) {
            $lines.Add("  VIKING_REPO_ROOT_HOST points at a folder that does not exist: clone Viking there")
            $lines.Add("  (git clone -b dev https://github.com/jamesra/Viking.git $($viking.Root)) or correct host.env.")
        }
        else {
            $lines.Add("  the checkout at $($viking.Root) is probably not on branch dev: git -C '$($viking.Root)' checkout dev")
        }
    }
    return ($lines -join [Environment]::NewLine)
}

function Get-VikingHostnameDefaults {
    <#
    .SYNOPSIS
      Derive VIKING_HOSTNAME_<SERVICE> = <sub>.<VIKING_DOMAIN> for any that are unset.
    #>
    param([hashtable]$Env)
    $subs = [ordered]@{
        IDENTITY         = 'identity'
        WEBSVC           = 'websvc'
        ANNOTATION       = 'annotation'
        CORRECTIONS      = 'corrections'
        SEGMENTATION     = 'segmentation'
        SEGMENTATIONDEMO = 'segmentationdemo'
        SEG_V3           = 'segmentation-v3'
        SEG_V4           = 'segmentation-v4'
        SEG_SEM_V1       = 'segmentation-sem-v1'
        GALLERY          = 'gallery'
        TEM_GALLERY      = 'gallery-tem'
        SEM_GALLERY      = 'gallery-sem'
    }
    $domain = $Env['VIKING_DOMAIN']
    $result = [ordered]@{}
    foreach ($k in $subs.Keys) {
        $name = "VIKING_HOSTNAME_$k"
        $v = $Env[$name]
        if ([string]::IsNullOrWhiteSpace($v) -and -not [string]::IsNullOrWhiteSpace($domain)) {
            $v = "$($subs[$k]).$domain"
        }
        if ($v) { $result[$name] = $v }
    }
    return $result
}

$script:SourceRevisionCache = @{}

function Get-SourceRevision {
    <#
    .SYNOPSIS
      HEAD commit of a checkout, suffixed -dirty when tracked files are modified; '' outside git.

    .DESCRIPTION
      Exported as STACK_SOURCE_REVISION so compose builds stamp org.opencontainers.image.revision.
      Cached per path for the life of the process.
    #>
    param([string]$Path)
    if (-not $Path) { return '' }
    if ($script:SourceRevisionCache.ContainsKey($Path)) { return $script:SourceRevisionCache[$Path] }
    $rev = ''
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $sha = & git -C $Path rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $sha) {
            $dirty = & git -C $Path status --porcelain --untracked-files=no 2>$null
            $rev = "$($sha.Trim())$(if ($dirty) { '-dirty' })"
        }
    }
    $script:SourceRevisionCache[$Path] = $rev
    return $rev
}

function Get-StackEnvironment {
    <#
    .SYNOPSIS
      Build the full env (host.env + host secrets + stack run.env + stack secrets.env + contract vars).

    .DESCRIPTION
      Later files win. Contract variables (STACK_*, DOCKER_CERTS_DIR, repo roots,
      STACK_SOURCE_REVISION, derived VIKING_HOSTNAME_*, VIKING_IDENTITY_URL, VIKING_IDENTITY_API_URL,
      TLS_CERT_NAME) are added when not already set.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Entry,
        [string]$Root = ''
    )
    $layout = Get-DockerHostLayout -Root $Root
    $dirs = Get-StackDirs -Stack $Entry.Key -Root $Root
    $envMap = Read-HostEnv -Root $Root
    foreach ($p in @($dirs.RunEnv, $dirs.SecretsEnv)) {
        foreach ($e in (Read-NornirDotEnvFile $p).GetEnumerator()) { $envMap[$e.Key] = $e.Value }
    }
    $contract = [ordered]@{
        NORNIR_DOCKER_USER_ROOT = $layout.Root
        STACK_NAME              = $Entry.Key
        STACK_RUN_DIR           = $dirs.Run
        STACK_SECRETS_DIR       = $dirs.Secrets
        STACK_DATA_DIR          = $dirs.Data
        STACK_LOGS_DIR          = $dirs.Logs
        DOCKER_CERTS_DIR        = $layout.Certs
        DOCKER_WORK_DIR         = $layout.Work
    }
    foreach ($k in $contract.Keys) {
        $envMap[$k] = ConvertTo-DockerBindPath $contract[$k]
    }
    foreach ($var in @('DEPLOY_REPO_ROOT_HOST', 'NORNIR_REPO_ROOT_HOST', 'VIKING_REPO_ROOT_HOST')) {
        if ([string]::IsNullOrWhiteSpace($envMap[$var])) {
            $r = Get-RepoRootFromEnv -VarName $var -HostEnv $envMap
            if ($r) { $envMap[$var] = $r }
        }
    }
    if ([string]::IsNullOrWhiteSpace($envMap['STACK_SOURCE_REVISION'])) {
        $envMap['STACK_SOURCE_REVISION'] = Get-SourceRevision -Path $Entry.RepoRoot
    }
    foreach ($e in (Get-VikingHostnameDefaults -Env $envMap).GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace($envMap[$e.Key])) { $envMap[$e.Key] = $e.Value }
    }
    # One identity issuer / WebApi URL for every identity client on the host (compose files fall back
    # to the same derivation when an older stack.ps1 does not export these).
    $identityHost = $envMap['VIKING_HOSTNAME_IDENTITY']
    if ([string]::IsNullOrWhiteSpace($envMap['VIKING_IDENTITY_URL']) -and $identityHost) {
        $envMap['VIKING_IDENTITY_URL'] = "https://$identityHost/"
    }
    if ([string]::IsNullOrWhiteSpace($envMap['VIKING_IDENTITY_API_URL']) -and $identityHost) {
        $envMap['VIKING_IDENTITY_API_URL'] = "https://$identityHost/webapi/"
    }
    if ([string]::IsNullOrWhiteSpace($envMap['TLS_CERT_NAME']) -and $envMap['VIKING_DOMAIN']) {
        $envMap['TLS_CERT_NAME'] = $envMap['VIKING_DOMAIN']
    }
    return $envMap
}

function Get-StackEnvFileArgs {
    param(
        [Parameter(Mandatory)][hashtable]$Entry,
        [string]$Root = ''
    )
    $layout = Get-DockerHostLayout -Root $Root
    $dirs = Get-StackDirs -Stack $Entry.Key -Root $Root
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @($layout.HostEnv, $layout.HostSecretsEnv, $dirs.RunEnv, $dirs.SecretsEnv)) {
        if (Test-Path -LiteralPath $p) {
            $list.Add('--env-file'); $list.Add($p)
        }
    }
    return , $list.ToArray()
}

function Expand-StackTemplate {
    <#
    .SYNOPSIS
      Replace {VAR} tokens in a registry string (e.g. HealthUrl) from an env map.
    #>
    param([string]$Text, [hashtable]$Env)
    if (-not $Text) { return $Text }
    return [regex]::Replace($Text, '\{([A-Z0-9_]+)\}', {
            param($m)
            $v = $Env[$m.Groups[1].Value]
            if ($null -eq $v) { return $m.Value }
            return $v
        })
}

function Test-PlaceholderValue {
    <#
    .SYNOPSIS
      True when a value is empty or still an example placeholder (REPLACE_ME / REPLACE_WITH_...).
    #>
    param([string]$Value)
    return ([string]::IsNullOrWhiteSpace($Value) -or $Value -match 'REPLACE_(ME|WITH)')
}

function Set-EnvFileValue {
    <#
    .SYNOPSIS
      Replace KEY=... in an env file (first uncommented occurrence); return $false when the key is absent.
    #>
    param([string]$Path, [string]$Key, [string]$Value)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $lines = @(Get-Content -LiteralPath $Path)
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*='
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match $pattern) {
            $lines[$i] = "$Key=$Value"
            Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
            return $true
        }
    }
    return $false
}

function Test-StackRequired {
    <#
    .SYNOPSIS
      Return a list of problems (missing run.env, empty REQUIRED keys, missing secret files).
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Entry,
        [Parameter(Mandatory)][hashtable]$Env,
        [string]$Root = ''
    )
    $problems = [System.Collections.Generic.List[string]]::new()
    $dirs = Get-StackDirs -Stack $Entry.Key -Root $Root
    if (-not $Entry.RepoRoot) { $problems.Add("$($Entry.RepoRootVar) is not set in host.env (this stack runs from that checkout)") }
    $example = if ($Entry.Example) { Join-DockerHostPath $Entry.RegistryRoot $Entry.Example } else { $null }
    if ($Entry.Example -and -not (Test-Path -LiteralPath $dirs.RunEnv)) {
        $problems.Add("missing $($dirs.RunEnv) (copy from $example)")
    }
    foreach ($k in @($Entry.Required)) {
        if (-not $k) { continue }
        if (Test-PlaceholderValue $Env[$k]) {
            $problems.Add("$k is empty or a placeholder (Run/$($Entry.Key)/$($Entry.Key).run.env, its secrets/secrets.env, or host.env)")
        }
    }
    foreach ($s in @($Entry.Secrets)) {
        if (-not $s) { continue }
        $sp = Join-DockerHostPath $dirs.Secrets $s
        if (-not (Test-Path -LiteralPath $sp)) { $problems.Add("missing secret file $sp") }
    }
    foreach ($o in (Get-StackComposeOverlays -EnvMap $Env)) {
        if (-not (Test-Path -LiteralPath $o)) { $problems.Add("STACK_COMPOSE_OVERLAYS names a missing file: $o") }
    }
    return , $problems.ToArray()
}

function Invoke-WithProcessEnv {
    <#
    .SYNOPSIS
      Run a scriptblock with extra process environment variables, then restore.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Env,
        [Parameter(Mandatory)][scriptblock]$Script
    )
    $saved = @{}
    foreach ($k in $Env.Keys) {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k, 'Process')
        [Environment]::SetEnvironmentVariable($k, [string]$Env[$k], 'Process')
    }
    try { & $Script }
    finally {
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k], 'Process') }
    }
}

function Get-StackComposeOverlays {
    <#
    .SYNOPSIS
      Extra compose files from STACK_COMPOSE_OVERLAYS (comma list in the run env), in order.

    .DESCRIPTION
      Host-specific variations of a stack (e.g. stacks/viking-segmentation/compose.macvlan.yaml) are
      overlays merged after the registry's ComposeFiles. Relative paths resolve against this repo.
    #>
    param([Parameter(Mandatory)][hashtable]$EnvMap)
    $raw = $EnvMap['STACK_COMPOSE_OVERLAYS']
    if ([string]::IsNullOrWhiteSpace($raw)) { return , @() }
    $deployRoot = Get-RepoRootFromEnv -VarName 'DEPLOY_REPO_ROOT_HOST' -HostEnv $EnvMap
    $files = foreach ($f in ($raw -split ',')) {
        $f = $f.Trim()
        if (-not $f) { continue }
        if ([System.IO.Path]::IsPathRooted($f)) { $f } else { Join-DockerHostPath $deployRoot $f }
    }
    return , @($files)
}

function Get-StackComposeBaseArgs {
    <#
    .SYNOPSIS
      docker compose arguments for a stack: project, env files, compose files plus overlays, profiles.

    .DESCRIPTION
      STACK_PROFILES in the stack's env replaces the registry's default Profiles (`none` turns them
      all off); -ExtraProfiles still adds to the result. Pass -EnvMap when the caller already has it.
    #>
    param(
        [Parameter(Mandatory)][hashtable]$Entry,
        [string[]]$ExtraProfiles = @(),
        [string]$Root = '',
        [hashtable]$EnvMap = $null
    )
    if ($null -eq $EnvMap) { $EnvMap = Get-StackEnvironment -Entry $Entry -Root $Root }
    $a = [System.Collections.Generic.List[string]]::new()
    $a.Add('compose')
    $project = if ($Entry.ComposeProject) { $Entry.ComposeProject } else { $Entry.Key }
    $a.Add('-p'); $a.Add($project)
    foreach ($x in (Get-StackEnvFileArgs -Entry $Entry -Root $Root)) { $a.Add($x) }
    foreach ($f in @($Entry.ComposeFiles)) {
        if (-not $f) { continue }
        $a.Add('-f'); $a.Add((Join-DockerHostPath $Entry.RepoRoot $f))
    }
    foreach ($f in (Get-StackComposeOverlays -EnvMap $EnvMap)) { $a.Add('-f'); $a.Add($f) }
    $profiles = @($Entry.Profiles)
    $override = $EnvMap['STACK_PROFILES']
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        $profiles = if ($override.Trim() -eq 'none') { @() } else { @($override -split '[,\s]+') }
    }
    foreach ($p in ($profiles + @($ExtraProfiles -split ",") | Where-Object { $_ } | Select-Object -Unique)) {
        $a.Add('--profile'); $a.Add($p)
    }
    return , $a.ToArray()
}

function Invoke-Docker {
    <#
    .SYNOPSIS
      Run docker with the console attached (no stdout capture); exit code in $script:Rc.
    #>
    param([Parameter(Mandatory)][string[]]$Arguments)
    Write-Host ("docker " + (($Arguments | ForEach-Object { if ($_ -match '\s') { "'$_'" } else { $_ } }) -join ' ')) -ForegroundColor DarkGray
    & docker @Arguments
    # Exit code goes to $script:Rc (not the output stream) so docker keeps the console/TTY.
    $script:Rc = $LASTEXITCODE
}

function Import-DockerTargets {
    <#
    .SYNOPSIS
      Load Run/_host/targets.psd1 (remote deploy targets). Returns @{} when absent.
    #>
    param([string]$Root = '')
    $l = Get-DockerHostLayout -Root $Root
    if (-not (Test-Path -LiteralPath $l.Targets)) { return @{} }
    $data = Import-PowerShellDataFile -LiteralPath $l.Targets
    return $data.Targets
}

function ConvertTo-RemoteArg {
    <#
    .SYNOPSIS
      Single-quote an argument for a remote pwsh/bash command line.
    #>
    param([string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

function Get-RemotePwshCommand {
    param(
        [Parameter(Mandatory)][hashtable]$Target,
        [Parameter(Mandatory)][string[]]$StackArgs
    )
    $root = $Target.Root
    $sep = if ($Target.Os -eq 'windows') { '\' } else { '/' }
    $launcher = "$root$sep" + 'stack.ps1'
    $quoted = ($StackArgs | ForEach-Object { ConvertTo-RemoteArg $_ }) -join ' '
    return "pwsh -NoLogo -NoProfile -File $(ConvertTo-RemoteArg $launcher) $quoted"
}

function Invoke-Ssh {
    param(
        [Parameter(Mandatory)][hashtable]$Target,
        [Parameter(Mandatory)][string]$Command,
        [switch]$Tty
    )
    $a = [System.Collections.Generic.List[string]]::new()
    if ($Tty) { $a.Add('-t') }
    foreach ($o in @($Target.SshOptions)) { if ($o) { $a.Add($o) } }
    $a.Add($Target.Ssh)
    $a.Add($Command)
    Write-Host ("ssh " + ($a -join ' ')) -ForegroundColor DarkGray
    & ssh @a
    $script:Rc = $LASTEXITCODE
}
