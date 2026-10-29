#Requires -Version 7.2
<#
.SYNOPSIS
  Add, change or remove a segmentation model server: stack.ps1 viking-segmentation model.

.DESCRIPTION
  A thin wrapper so the command works from any folder once this scripts/ folder is on PATH:
  it runs stack.ps1 from this checkout with `viking-segmentation model` first and passes every other argument
  through. segmentation-model.sh is the same wrapper for bash.

.EXAMPLE
  segmentation-model v5 v5/serve_epoch4.pt
#>
& (Join-Path $PSScriptRoot '..' 'stack.ps1') 'viking-segmentation' 'model' @args
exit $LASTEXITCODE
