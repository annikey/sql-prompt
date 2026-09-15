# Windows PowerShell 5.1. No installation or global configuration changes.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Read-JsonFile([string]$Path) {
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}
function Write-Utf8([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if (!(Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding($false)))
}
function Write-JsonFile([string]$Path, $Value) { Write-Utf8 $Path (ConvertTo-Json -InputObject $Value -Depth 30) }
function Resolve-LocalPath([string]$Base, [string]$Value) {
    $expanded = [Environment]::ExpandEnvironmentVariables($Value)
    if (![IO.Path]::IsPathRooted($expanded)) { $expanded = Join-Path $Base $expanded }
    [IO.Path]::GetFullPath($expanded)
}
function Resolve-ProjectFile([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Project paths must be relative without '..': $Relative"
    }
    $full = Resolve-LocalPath $Root $Relative
    if (!$full.StartsWith($Root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) { throw "Path outside project: $Relative" }
    $full
}
function Invoke-Git([string]$Root, [string[]]$Arguments) {
    $output = & git -C $Root @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git failed: $($output -join [Environment]::NewLine)" }
    ($output -join "`n").TrimEnd()
}
function Get-WorkStatus([string]$Root) {
    Invoke-Git $Root @('status','--porcelain=v1','--untracked-files=all','--','.',':(exclude).ai-night-run')
}
function Get-ChangedFiles([string]$Root) {
    $tracked = Invoke-Git $Root @('-c','core.quotepath=false','diff','--name-only','HEAD','--','.',':(exclude).ai-night-run')
    $new = Invoke-Git $Root @('-c','core.quotepath=false','ls-files','--others','--exclude-standard','--','.',':(exclude).ai-night-run')
    @(@($tracked -split "`n") + @($new -split "`n") | Where-Object { $_ } | Sort-Object -Unique)
}
function Get-Hash([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash } else { '' }
}
function Read-Queue([string]$Path) {
    $items = @(); $seen = @{}
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ($line -notmatch '^\s*-\s+\[') { continue }
        $pattern = '^- \[(?<check>[ xX])\] (?<id>[A-Za-z0-9_-]+) \| mode=(?<mode>plan|implement) \| status=(?<status>draft|night-ready|running|ready-for-review|blocked|failed|done) \| doc=(?<doc>[^|]+) \| depends=(?<deps>[^|]+)$'
        if ($line -notmatch $pattern) { throw "Invalid queue line: $line" }
        $m = $Matches.Clone()
        if ($seen.ContainsKey($m.id)) { throw "Duplicate queue ID: $($m.id)" }
        $seen[$m.id] = $true
        $done = $m.check -match '[xX]'
        if ($done -ne ($m.status -eq 'done')) { throw "Checkbox/status mismatch: $($m.id)" }
        $deps = @()
        if ($m.deps.Trim() -ne '-') {
            $deps = @($m.deps.Split(',') | ForEach-Object { $_.Trim() })
            foreach ($dep in $deps) {
                if ($dep -notmatch '^[A-Za-z0-9_-]+$' -or $dep -eq $m.id) { throw "Invalid dependency: $dep" }
            }
        }
        $items += [pscustomobject]@{ id=$m.id; mode=$m.mode; status=$m.status; doc=$m.doc.Trim(); depends=$deps; done=$done; line=$line }
    }
    foreach ($item in $items) {
        foreach ($dep in $item.depends) { if (!$seen.ContainsKey($dep)) { throw "Unknown dependency: $dep" } }
    }
    $remaining = @($items); $visited = @{}
    while ($remaining.Count -gt 0) {
        $ready = @($remaining | Where-Object {
            $unseen = @($_.depends | Where-Object { !$visited.ContainsKey($_) })
            $unseen.Count -eq 0
        })
        if ($ready.Count -eq 0) { throw 'Dependency cycle in queue.' }
        foreach ($item in $ready) { $visited[$item.id] = $true }
        $remaining = @($remaining | Where-Object { !$visited.ContainsKey($_.id) })
    }
    $items
}
function Set-QueueStatus([string]$Path, [string]$Id, [string]$Status) {
    $items = @(Read-Queue $Path); $item = @($items | Where-Object { $_.id -eq $Id })
    if ($item.Count -ne 1) { throw "Queue ID not found: $Id" }
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $check = ' '; if ($Status -eq 'done') { $check = 'x' }
    $replacement = $item[0].line -replace '^- \[[ xX]\]', "- [$check]"
    $replacement = $replacement -replace '\| status=[a-z-]+ \|', "| status=$Status |"
    Write-Utf8 $Path ($text.Replace($item[0].line, $replacement))
}
function Select-ReadyTask($Items, [bool]$AllowVerifiedDependencies) {
    $status = @{}; foreach ($item in $Items) { $status[$item.id] = $item }
    foreach ($item in $Items) {
        if ($item.status -ne 'night-ready' -or $item.done) { continue }
        $ready = $true
        foreach ($dep in $item.depends) {
            $d = $status[$dep]
            if (!$d.done -and !($AllowVerifiedDependencies -and $d.status -eq 'ready-for-review' -and $d.mode -eq 'implement')) {
                $ready = $false
            }
        }
        if ($ready) { return $item }
    }
    return $null
}
function Get-NightlyConfig([string]$Path) {
    $full = (Resolve-Path -LiteralPath $Path).Path; $cfg = Read-JsonFile $full; $base = Split-Path -Parent $full
    if ($cfg.schemaVersion -ne 1) { throw 'Unsupported schemaVersion.' }
    if ($cfg.maxTasks -lt 1 -or $cfg.maxTasks -gt 100) { throw 'maxTasks must be 1..100.' }
    if ($cfg.maxRunMinutes -lt 1 -or $cfg.taskTimeoutMinutes -lt 1 -or $cfg.verificationTimeoutMinutes -lt 1) { throw 'Timeouts must be positive.' }
    if ($cfg.startTimeLocal -notmatch '^\d{2}:\d{2}$' -or $cfg.stopTimeLocal -notmatch '^\d{2}:\d{2}$') { throw 'Use HH:mm for window times.' }
    [void][TimeSpan]::Parse($cfg.startTimeLocal); [void][TimeSpan]::Parse($cfg.stopTimeLocal)
    $cfg.logRoot = Resolve-LocalPath $base $cfg.logRoot; $cfg.stopFile = Resolve-LocalPath $base $cfg.stopFile
    $cfg.extraPath = @($cfg.extraPath | ForEach-Object { Resolve-LocalPath $base $_ })
    $cfg.sharedInstructionFiles = @($cfg.sharedInstructionFiles | ForEach-Object { Resolve-LocalPath $base $_ })
    foreach ($file in $cfg.sharedInstructionFiles) {
        if (!(Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing instructions: $file" }
    }
    $names = @{}
    foreach ($p in $cfg.projects) {
        if ($p.id -notmatch '^[a-zA-Z0-9_-]+$' -or $names.ContainsKey($p.id)) { throw "Invalid/duplicate project ID: $($p.id)" }
        $names[$p.id] = $true
        $p.repoPath = Resolve-LocalPath $base $p.repoPath; $p.worktreePath = Resolve-LocalPath $base $p.worktreePath
        if ($p.model -notmatch '^[^/\s]+/[^ \t\r\n]+$' -or $p.model -match 'REPLACE') { throw "Set corporate provider/model for $($p.id)." }
        foreach ($path in @($p.queuePath) + @($p.contextFiles) + @($p.verificationScript | Where-Object { $_ })) {
            [void](Resolve-ProjectFile $p.worktreePath $path)
        }
        foreach ($pattern in $p.allowedEditPaths) {
            if ([IO.Path]::IsPathRooted($pattern) -or $pattern -match '\.\.|\\|[\[\]]' -or $pattern -in @('*','**')) {
                throw "Use scoped relative edit patterns with '/': $pattern"
            }
        }
    }
    $cfg
}
function Assert-Worktree($Project, [switch]$RequireClean) {
    $root = $Project.worktreePath
    if ($root.TrimEnd('\','/') -eq $Project.repoPath.TrimEnd('\','/')) { throw "Separate worktree required: $($Project.id)" }
    $top = Invoke-Git $root @('rev-parse','--show-toplevel')
    if ([IO.Path]::GetFullPath($top).TrimEnd('\','/') -ne $root.TrimEnd('\','/')) { throw "Not a repository root: $root" }
    $common = Invoke-Git $root @('rev-parse','--git-common-dir')
    $sourceCommon = Invoke-Git $Project.repoPath @('rev-parse','--git-common-dir')
    if ((Resolve-LocalPath $root $common) -ne (Resolve-LocalPath $Project.repoPath $sourceCommon)) { throw "Worktree belongs to another repository: $root" }
    $branch = Invoke-Git $root @('branch','--show-current')
    if ($branch -ne $Project.expectedBranch -or !$branch) { throw "Unexpected branch: $branch" }
    if ($RequireClean -and (Get-WorkStatus $root)) { throw "Worktree has unreviewed changes: $root" }
}
function Get-WindowDeadline($Config, [switch]$Manual) {
    $now = Get-Date; $deadline = $now.AddMinutes($Config.maxRunMinutes)
    if (!$Manual) {
        $start = $now.Date.Add([TimeSpan]::Parse($Config.startTimeLocal))
        $end = $now.Date.Add([TimeSpan]::Parse($Config.stopTimeLocal))
        if ($end -le $start) {
            if ($now -lt $end) { $start = $start.AddDays(-1) } else { $end = $end.AddDays(1) }
        }
        if ($now -lt $start -or $now -ge $end) { throw 'Outside the configured night window.' }
        if ($end -lt $deadline) { $deadline = $end }
    }
    $deadline.ToUniversalTime()
}
function Get-EditPatterns($Project, $Task, [string]$ResultRelative) {
    $patterns = @($Task.doc, $ResultRelative)
    if ($Task.mode -eq 'implement') { $patterns += @($Project.allowedEditPaths) }
    $patterns
}
function Get-ProtectedPatterns($Project) {
    @($Project.queuePath, $Project.verificationScript, 'AGENTS.md', 'opencode.json','opencode.jsonc',
        '.opencode/*','.git','.git/*','.gitignore','.gitattributes','.gitmodules','.ai/*','.github/*',
        '.gitlab-ci.yml','Jenkinsfile','**/AGENTS.md','**/.env*','.env*','*.pem','*.key') | Where-Object { $_ }
}
function Test-ProtectedPath($Project, [string]$Path) {
    foreach ($pattern in (Get-ProtectedPatterns $Project)) { if ($Path.Replace('\','/') -like $pattern) { return $true } }
    $false
}
function New-AgentConfig($Project, $Task, [string]$ResultRelative) {
    $edits = [ordered]@{ '*'='deny' }
    foreach ($pattern in (Get-EditPatterns $Project $Task $ResultRelative)) {
        $edits[$pattern] = 'allow'
        $edits[($Project.worktreePath.Replace('\','/').TrimEnd('/') + '/' + $pattern)] = 'allow'
    }
    foreach ($pattern in (Get-ProtectedPatterns $Project)) {
        $edits[$pattern] = 'deny'
        $edits[($Project.worktreePath.Replace('\','/').TrimEnd('/') + '/' + $pattern)] = 'deny'
    }
    $permission = [ordered]@{
        '*'='deny'
        read=[ordered]@{ '*'='allow'; '*.env'='deny'; '*.env.*'='deny'; '*.pem'='deny'; '*.key'='deny'; '*auth.json'='deny' }
        glob='allow'; grep='allow'; edit=$edits
        bash='deny'; task='deny'; question='deny'; external_directory='deny'; doom_loop='deny'
    }
    [ordered]@{
        share='disabled'; permission=$permission
        agent=@{ 'ai-fosql-night'=@{ description='Explicit single-ticket nightly worker'; mode='primary'; model=$Project.model; permission=$permission } }
    }
}
function Invoke-TimedWorker($Request, [string]$Directory, [int]$TimeoutSeconds, [DateTime]$DeadlineUtc, [string]$StopFile) {
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $requestPath = Join-Path $Directory 'request.json'; Write-JsonFile $requestPath $Request
    $worker = Join-Path $PSScriptRoot 'Worker.ps1'
    $command = "& '" + $worker.Replace("'","''") + "' -RequestPath '" + $requestPath.Replace("'","''") + "'"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $shell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $p = Start-Process -FilePath $shell -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',$encoded) `
        -WorkingDirectory $Request.workingDirectory -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $Directory 'stdout.log') -RedirectStandardError (Join-Path $Directory 'stderr.log')
    # Retain the process handle so Windows PowerShell can read ExitCode after exit.
    $processHandle = $p.Handle
    $until = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds); $reason = 'exited'
    try {
        while (!$p.WaitForExit(500)) {
            if (Test-Path -LiteralPath $StopFile) { $reason = 'stop-file'; break }
            if ([DateTime]::UtcNow -ge $DeadlineUtc) { $reason = 'night-deadline'; break }
            if ([DateTime]::UtcNow -ge $until) { $reason = 'timeout'; break }
        }
    } finally {
        if (!$p.HasExited) {
            & "$env:SystemRoot\System32\taskkill.exe" /PID $p.Id /T /F | Out-Null
            if (!$p.WaitForExit(5000)) { throw "Cannot terminate worker PID $($p.Id); stop manually." }
        }
    }
    [pscustomobject]@{ exitCode=$p.ExitCode; reason=$reason }
}
