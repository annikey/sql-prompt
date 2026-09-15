#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$ConfigPath)
. "$PSScriptRoot\Common.ps1"
try {
    if ($env:OS -ne 'Windows_NT') { throw 'This launcher targets Windows PowerShell 5.1.' }
    $cfg = Get-NightlyConfig $ConfigPath
    if ($env:OPENCODE_CONFIG_CONTENT) { throw 'Existing OPENCODE_CONFIG_CONTENT must be integrated by the maintainer, not overwritten.' }
    $env:PATH = (@($cfg.extraPath) -join ';') + ';' + $env:PATH
    $exe = (Get-Command $cfg.openCodeCommand -CommandType Application -ErrorAction Stop).Source
    $version = & $exe --version
    if ($LASTEXITCODE -ne 0) { throw 'OpenCode --version failed.' }
    Write-Host "OpenCode: $exe ($version)"
    $helpText = (& $exe run --help 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'OpenCode run --help failed.' }
    foreach ($flag in @('--file','--format','--model','--agent')) {
        if (!$helpText.Contains($flag)) { throw "Installed OpenCode does not advertise $flag." }
    }
    foreach ($p in @($cfg.projects | Where-Object { $_.enabled })) {
        Assert-Worktree $p -RequireClean
        $items = @(Read-Queue (Resolve-ProjectFile $p.worktreePath $p.queuePath))
        foreach ($f in $p.contextFiles) {
            if (!(Test-Path -LiteralPath (Resolve-ProjectFile $p.worktreePath $f) -PathType Leaf)) { throw "Missing context file: $f" }
        }
        foreach ($t in $items) {
            if (Test-ProtectedPath $p $t.doc) { throw "Ticket document uses protected path: $($t.doc)" }
            $doc = Resolve-ProjectFile $p.worktreePath $t.doc
            if (!(Test-Path -LiteralPath $doc -PathType Leaf)) { throw "Missing ticket document: $doc" }
            if ($t.status -eq 'running') { throw "Unresolved interrupted task: $($t.id)" }
            if ($t.mode -eq 'implement' -and $t.status -eq 'night-ready') {
                if ((Get-Content -LiteralPath $doc -Raw -Encoding UTF8) -notmatch '<!-- plan-approved -->') { throw "Missing human approval marker: $($t.id)" }
                if (!$p.verificationScript -or !(Test-Path -LiteralPath (Resolve-ProjectFile $p.worktreePath $p.verificationScript))) {
                    throw "Implementation needs a reviewed verificationScript: $($p.id)"
                }
            }
        }
        $ready = @($items | Where-Object { $_.status -eq 'night-ready' })
        Write-Host "$($p.id): branch=$($p.expectedBranch); queued=$($ready.Count); model=$($p.model)"
    }
    Write-Host 'Configuration checked; no model inference requested. Provider, permissions and scheduling need a manual smoke test.'
} catch { Write-Error $_; exit 1 }
