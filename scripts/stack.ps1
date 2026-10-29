#Requires -Version 7.2
<#
.SYNOPSIS
  One command for every Nornir/Viking container stack (stack.ps1 of this checkout).

.DESCRIPTION
  A thin wrapper so the command works from any folder once this scripts/ folder is on PATH:
  it runs stack.ps1 from this checkout and passes every other argument
  through. stack.sh is the same wrapper for bash.

.EXAMPLE
  stack doctor
#>
& (Join-Path $PSScriptRoot '..' 'stack.ps1')  @args
exit $LASTEXITCODE
