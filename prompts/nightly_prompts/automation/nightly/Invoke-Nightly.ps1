#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ConfigPath,
    [switch]$DryRun,
    [switch]$Manual
)
. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Run-OneTicket.ps1"
$lock = $null; $runDir = $null; $summary = @(); $exitCode = 0
try {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows PowerShell 5.1 is required.' }
    $cfg = Get-NightlyConfig $ConfigPath
    if (!$DryRun -and !$cfg.runtimeApproved) { throw 'Read README and approve the local runtime before live runs (runtimeApproved=true).' }
    if ($env:OPENCODE_CONFIG_CONTENT) { throw 'Existing OPENCODE_CONFIG_CONTENT detected. Ask the maintainer to integrate the corporate inline config; it will not be overwritten.' }
    New-Item -ItemType Directory -Path $cfg.logRoot -Force | Out-Null
    # File lock is automatically released if the host dies. Keep the same logRoot for all schedules.
    $lock = [IO.File]::Open((Join-Path $cfg.logRoot 'nightly.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    if (!$DryRun) {
        $runDir = Join-Path $cfg.logRoot ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
        New-Item -ItemType Directory -Path $runDir | Out-Null
    }
    if (Test-Path -LiteralPath $cfg.stopFile) { throw "STOP file exists: $($cfg.stopFile)" }
    $deadline = Get-WindowDeadline $cfg -Manual:($Manual -or $DryRun)
    $env:PATH = (@($cfg.extraPath) -join ';') + ';' + $env:PATH
    $exe = (Get-Command $cfg.openCodeCommand -CommandType Application -ErrorAction Stop).Source
    $projects = @($cfg.projects | Where-Object { $_.enabled })
    if ($projects.Count -eq 0) { throw 'No enabled projects.' }
    $paths = @($projects | ForEach-Object { $_.worktreePath.ToLowerInvariant() })
    if (@($paths | Sort-Object -Unique).Count -ne $paths.Count) { throw 'Duplicate worktree paths.' }
    # Preflight all enabled projects before changing any queue.
    foreach ($p in $projects) {
        Assert-Worktree $p -RequireClean
        $items = @(Read-Queue (Resolve-ProjectFile $p.worktreePath $p.queuePath))
        foreach ($t in $items) {
            $doc = Resolve-ProjectFile $p.worktreePath $t.doc
            if (!(Test-Path -LiteralPath $doc -PathType Leaf)) { throw "Missing ticket document: $doc" }
            if (Test-ProtectedPath $p $t.doc) { throw "Invalid ticket document path: $($t.doc)" }
            if ($t.status -eq 'running') { throw "Interrupted task requires review: $($t.id)" }
            if ($t.status -eq 'night-ready' -and $t.mode -eq 'implement') {
                if ((Get-Content -LiteralPath $doc -Raw -Encoding UTF8) -notmatch '<!-- plan-approved -->') { throw "Plan not approved: $($t.id)" }
                if (!$p.verificationScript -or !(Test-Path -LiteralPath (Resolve-ProjectFile $p.worktreePath $p.verificationScript) -PathType Leaf)) {
                    throw "Missing verifier for project $($p.id)"
                }
            }
        }
        foreach ($f in $p.contextFiles) {
            if (!(Test-Path -LiteralPath (Resolve-ProjectFile $p.worktreePath $f))) { throw "Missing context: $f" }
        }
    }
    if ($DryRun) {
        foreach ($p in $projects) {
            $items = @(Read-Queue (Resolve-ProjectFile $p.worktreePath $p.queuePath))
            $candidate = Select-ReadyTask $items $cfg.allowVerifiedDependencies
            $id = '(none)'; if ($null -ne $candidate) { $id = $candidate.id }
            Write-Host "$($p.id): next=$id; cwd=$($p.worktreePath); model=$($p.model)"
        }
        Write-Host "Dry run: no model call or task edits; global cap=$($cfg.maxTasks)."
    } else {
        $halt = $false
        # Round-robin: at most one task per project per pass; no parallel agents.
        while (!$halt -and $summary.Count -lt $cfg.maxTasks -and [DateTime]::UtcNow -lt $deadline) {
            $progress = $false
            foreach ($p in $projects) {
                if ($summary.Count -ge $cfg.maxTasks -or [DateTime]::UtcNow -ge $deadline) { break }
                if (Test-Path -LiteralPath $cfg.stopFile) { $halt=$true; break }
                $items = @(Read-Queue (Resolve-ProjectFile $p.worktreePath $p.queuePath))
                $t = Select-ReadyTask $items $cfg.allowVerifiedDependencies
                if ($null -eq $t) { continue }
                $progress = $true
                Write-Host "Starting $($p.id)/$($t.id) [$($t.mode)]"
                $r = Invoke-OneTicket $cfg $p $t $runDir $deadline $exe
                $summary += $r
                Write-JsonFile (Join-Path $runDir 'summary.json') $summary
                Write-Host "$($r.status): $($r.message)"
                if ($r.status -ne 'ready-for-review') { $halt=$true; $exitCode=2; break }
            }
            if (!$progress) { break }
        }
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    if ($runDir) { Write-Utf8 (Join-Path $runDir 'runner-error.txt') $_.Exception.ToString() }
    $exitCode=1
} finally {
    if ($runDir) {
        $lines = @('# Nightly report', '', "Started directory: $runDir", '', '| Project | Ticket | Mode | Result |', '|---|---|---|---|')
        foreach ($r in $summary) { $lines += "| $($r.project) | $($r.ticket) | $($r.mode) | $($r.status) |" }
        if ($summary.Count -eq 0) { $lines += ''; $lines += 'No task completed; check runner-error.txt or the queue dependencies.' }
        Write-Utf8 (Join-Path $runDir 'report.md') ($lines -join "`n")
        Write-Utf8 (Join-Path $cfg.logRoot 'latest-run.txt') $runDir
    }
    if ($null -ne $lock) { $lock.Dispose() }
}
exit $exitCode
