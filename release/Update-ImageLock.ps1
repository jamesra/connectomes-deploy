#Requires -Version 7.2
<#
.SYNOPSIS
  Resolve every image in release/images.psd1 against its registry and rewrite the file with digests.

.DESCRIPTION
  release/images.psd1 is this repo's equivalent of submodule pointers: the exact image each stack
  runs for this release. You choose the Repository and Tag of each entry; this script looks each
  one up with `docker buildx imagetools inspect` and fills in Digest (the manifest or index digest
  that `docker pull <Repository>@<Digest>` fetches), Revision and Source (from the image's OCI labels),
  and Created. It changes nothing in the registry.

  Release flow: build and push the images (nornir-docker/docker-push.ps1), set the Tag of each entry
  to the versioned tag that was pushed, run this script, review the diff, commit.

.PARAMETER Path
  Lock file. Default: images.psd1 next to this script.

.PARAMETER Name
  Only refresh these entries (keys in the file). Default: all.

.PARAMETER Check
  Do not write. Exit 1 when any entry's registry digest differs from the recorded Digest (or the
  tag cannot be resolved), so a release can verify that its pins still match the registry.

.EXAMPLE
  pwsh release/Update-ImageLock.ps1

.EXAMPLE
  pwsh release/Update-ImageLock.ps1 -Check
#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path $PSScriptRoot 'images.psd1'),
    [string[]]$Name = @(),
    [switch]$Check
)

$ErrorActionPreference = 'Stop'

function Get-RegistryImageInfo {
    <#
    .SYNOPSIS
      Digest, labels and created time of <Reference> from the registry (amd64 config for multi-arch indexes).
    #>
    param([Parameter(Mandatory)][string]$Reference)
    $manifest = (& docker buildx imagetools inspect $Reference --format '{{json .Manifest}}' 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "imagetools inspect $Reference failed: $($manifest.Trim())" }
    $image = (& docker buildx imagetools inspect $Reference --format '{{json .Image}}' 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw "imagetools inspect $Reference failed: $($image.Trim())" }
    $m = $manifest | ConvertFrom-Json -AsHashtable
    $i = $image | ConvertFrom-Json -AsHashtable
    if (-not $i.ContainsKey('config')) {
        $i = if ($i.ContainsKey('linux/amd64')) { $i['linux/amd64'] } else { $i[@($i.Keys)[0]] }
    }
    $labels = if ($i.config -and $i.config.Labels) { $i.config.Labels } else { @{} }
    return [ordered]@{
        Digest   = $m.digest
        Revision = "$($labels['org.opencontainers.image.revision'])"
        Source   = "$($labels['org.opencontainers.image.source'])"
        Created  = "$($i.created)"
    }
}

function ConvertTo-Psd1Value {
    param($Value)
    if ($Value -is [array]) { return '@(' + (($Value | ForEach-Object { ConvertTo-Psd1Value $_ }) -join ', ') + ')' }
    return "'" + ("$Value" -replace "'", "''") + "'"
}

$lock = Import-PowerShellDataFile -LiteralPath $Path
$header = @(Get-Content -LiteralPath $Path | Where-Object { $_ -match '^\s*#' } | Select-Object -First 20)
$fields = @('Repository', 'Tag', 'Digest', 'Source', 'Revision', 'Created', 'Stacks')
$problems = 0
foreach ($key in ($lock.Images.Keys | Sort-Object)) {
    if ($Name.Count -and $Name -notcontains $key) { continue }
    $e = $lock.Images[$key]
    $ref = "$($e.Repository):$($e.Tag)"
    try { $info = Get-RegistryImageInfo -Reference $ref }
    catch { Write-Warning "[$key] $($_.Exception.Message)"; $problems++; continue }
    if ($Check) {
        if ($info.Digest -ne $e.Digest) { Write-Warning "[$key] $ref is $($info.Digest), lock has $($e.Digest)"; $problems++ }
        else { Write-Host "[$key] $ref ok" }
        continue
    }
    if ($info.Digest -ne $e.Digest) { Write-Host "[$key] $ref -> $($info.Digest)" -ForegroundColor Yellow } else { Write-Host "[$key] $ref unchanged" }
    $e.Digest = $info.Digest
    $e.Created = $info.Created
    if ($info.Revision) { $e.Revision = $info.Revision }
    if ($info.Source) { $e.Source = $info.Source }
}
if ($Check) {
    if ($problems) { Write-Host "$problems pin(s) do not match the registry." -ForegroundColor Red; exit 1 }
    Write-Host 'All pins match the registry.' -ForegroundColor Green; exit 0
}

$lines = [System.Collections.Generic.List[string]]::new()
foreach ($h in $header) { $lines.Add($h) }
$lines.Add('@{')
$lines.Add('    Images = @{')
foreach ($key in ($lock.Images.Keys | Sort-Object)) {
    $e = $lock.Images[$key]
    $lines.Add("        '$key' = @{")
    foreach ($f in $fields) {
        $v = if ($f -eq 'Stacks') { , @($e[$f] | Where-Object { $_ }) } elseif ($e.ContainsKey($f)) { $e[$f] } else { '' }
        $lines.Add(('            {0,-10} = {1}' -f $f, (ConvertTo-Psd1Value $v)))
    }
    $lines.Add('        }')
}
$lines.Add('    }')
$lines.Add('}')
Set-Content -LiteralPath $Path -Value $lines -Encoding utf8
Write-Host "Wrote $Path$(if ($problems) { " ($problems entr$(if ($problems -eq 1) { 'y' } else { 'ies' }) not resolved; see warnings)" })"
if ($problems) { exit 1 }
