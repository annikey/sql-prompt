#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [Parameter(Mandatory=$true)][string]$Repository,
    [Parameter(Mandatory=$true)][string]$Destination,
    [Parameter(Mandatory=$true)][string]$Branch,
    [Parameter(Mandatory=$true)][string]$BaseRef
)
. "$PSScriptRoot\Common.ps1"
$repo = (Resolve-Path -LiteralPath $Repository).Path
$dest = Resolve-LocalPath (Get-Location).Path $Destination
if (Test-Path -LiteralPath $dest) { throw "Destination exists; nothing overwritten: $dest" }
if (Invoke-Git $repo @('status','--porcelain=v1')) { throw 'Commit the task plan and source changes before creating a worktree.' }
[void](Invoke-Git $repo @('check-ref-format','--branch',$Branch))
$commit = Invoke-Git $repo @('rev-parse','--verify',"$BaseRef^{commit}")
if ($PSCmdlet.ShouldProcess($dest, "Create branch $Branch from $commit")) {
    [void](Invoke-Git $repo @('worktree','add','-b',$Branch,$dest,$commit))
    Write-Host "Created $dest on $Branch. No fetch/push, reset or cleanup performed."
}
