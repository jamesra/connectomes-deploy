#Requires -Version 7.2
<#
.SYNOPSIS
  Create the host layout and copy the stack templates (Initialize-DockerHost.ps1 of this checkout).

.DESCRIPTION
  A thin wrapper so the command works from any folder once this scripts/ folder is on PATH:
  it runs Initialize-DockerHost.ps1 from this checkout and passes every other argument
  through. initialize-dockerhost.sh is the same wrapper for bash.

.EXAMPLE
  initialize-dockerhost -Role compute -Stacks nornir-build,viking-segmentation
#>
& (Join-Path $PSScriptRoot '..' 'Initialize-DockerHost.ps1')  @args
exit $LASTEXITCODE
