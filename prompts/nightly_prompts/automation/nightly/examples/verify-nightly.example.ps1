#Requires -Version 5.1
# Copy to the PROJECT as .ai/verify-nightly.ps1 and replace this body.
param(
    [Parameter(Mandatory=$true)][string]$ProjectPath,
    [Parameter(Mandatory=$true)][string]$TicketId
)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $ProjectPath
# Use reviewed LOCAL commands, propagate every native exit code immediately.
# Example shape only (do not enable without reviewing the actual project):
# & .\gradlew.bat test --no-daemon
# if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
# Write-Output "Verified $TicketId"
# exit 0
Write-Error 'Configure real project checks before enabling implementation tasks.'
exit 2
