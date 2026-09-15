# Internal function used by Invoke-Nightly.ps1.
function Invoke-OneTicket($Config, $Project, $Task, [string]$RunDirectory, [DateTime]$DeadlineUtc, [string]$Executable) {
    $root = $Project.worktreePath
    $queuePath = Resolve-ProjectFile $root $Project.queuePath
    $docPath = Resolve-ProjectFile $root $Task.doc
    $head = Invoke-Git $root @('rev-parse','HEAD')
    $docHash = Get-Hash $docPath
    $before = @{}
    foreach ($f in (Get-ChangedFiles $root)) { $before[$f] = Get-Hash (Join-Path $root $f) }
    $outDir = Join-Path $RunDirectory ($Project.id + '--' + $Task.id)
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $relative = '.ai-night-run/' + [Guid]::NewGuid().ToString('N')
    $packetPath = Resolve-ProjectFile $root ($relative + '/prompt.md')
    $resultRelative = $relative + '/result.json'
    $resultPath = Resolve-ProjectFile $root $resultRelative
    $state = [ordered]@{
        project=$Project.id; ticket=$Task.id; mode=$Task.mode; status='running'
        startedUtc=[DateTime]::UtcNow.ToString('o'); finishedUtc=$null
        initialHead=$head; worktree=$root; output=$outDir; message=''; changedFiles=@()
    }
    $verifier = ''
    if ($Project.verificationScript) { $verifier = Resolve-ProjectFile $root $Project.verificationScript }
    $verifierHash = ''; if ($verifier) { $verifierHash = Get-Hash $verifier }
    Set-QueueStatus $queuePath $Task.id 'running'
    $queueHash = Get-Hash $queuePath
    Write-JsonFile (Join-Path $outDir 'state.json') $state
    try {
        $promptsRoot = Join-Path $PSScriptRoot 'prompts'
        $text = Get-Content -LiteralPath (Join-Path $promptsRoot 'night-contract.md') -Raw -Encoding UTF8
        $modePrompt = 'plan-ticket.md'
        if ($Task.mode -eq 'implement') { $modePrompt = 'implement-ticket.md' }
        $text += "`n`n" + (Get-Content -LiteralPath (Join-Path $promptsRoot $modePrompt) -Raw -Encoding UTF8)
        $details = [ordered]@{
            ticketId=$Task.id; mode=$Task.mode; ticketDocument=$Task.doc
            queue=$Project.queuePath; resultFile=$resultRelative
            allowedEdits=@(Get-EditPatterns $Project $Task $resultRelative)
        } | ConvertTo-Json -Depth 10
        $text += "`n`n## Run parameters`n$details`n"
        foreach ($f in $Project.contextFiles) {
            $text += "`n`n## Project instructions: $f`n"
            $text += Get-Content -LiteralPath (Resolve-ProjectFile $root $f) -Raw -Encoding UTF8
        }
        foreach ($f in $Config.sharedInstructionFiles) {
            $text += "`n`n## Optional shared instructions: $(Split-Path -Leaf $f)`n"
            $text += Get-Content -LiteralPath $f -Raw -Encoding UTF8
        }
        Write-Utf8 $packetPath $text
        Write-Utf8 (Join-Path $outDir 'prompt.md') $text
        $inline = New-AgentConfig $Project $Task $resultRelative
        $req = [ordered]@{
            kind='opencode'; executable=$Executable; workingDirectory=$root; extraPath=$Config.extraPath
            inlineConfig=$inline
            arguments=@('run','Follow the attached single-ticket instructions.',
                '--model',$Project.model,'--agent','ai-fosql-night','--format','json','--file',$packetPath)
        }
        $process = Invoke-TimedWorker $req (Join-Path $outDir 'agent') ([int]($Config.taskTimeoutMinutes * 60)) $DeadlineUtc $Config.stopFile
        if ($process.reason -ne 'exited' -or $process.exitCode -ne 0) {
            throw "Agent process: $($process.reason), exit=$($process.exitCode)"
        }
        # Some OpenCode versions emit an error event while returning exit code 0.
        foreach ($line in (Get-Content -LiteralPath (Join-Path $outDir 'agent/stdout.log') -Encoding UTF8)) {
            try { $event = $line | ConvertFrom-Json } catch { continue }
            if ($event.PSObject.Properties['type'] -and $event.type -eq 'error') { throw 'OpenCode emitted an error event. See agent logs.' }
        }
        Assert-Worktree $Project
        if ((Invoke-Git $root @('rev-parse','HEAD')) -ne $head) { throw 'Agent changed Git HEAD; manual review required.' }
        if ((Get-Hash $queuePath) -ne $queueHash) { throw 'Agent changed queue; manual review required.' }
        $changedThisTask = @()
        $auditFiles = @(@(Get-ChangedFiles $root) + @($before.Keys) | Sort-Object -Unique)
        foreach ($f in $auditFiles) {
            $hash = Get-Hash (Join-Path $root $f)
            if ($before.ContainsKey($f) -and $before[$f] -eq $hash) { continue }
            if ($f -eq $Project.queuePath) { continue }
            $changedThisTask += $f
            if (Test-ProtectedPath $Project $f) { throw "Protected file changed: $f" }
            $allowed = $false
            foreach ($pattern in (Get-EditPatterns $Project $Task $resultRelative)) {
                if ($f -like $pattern) { $allowed = $true }
            }
            if (!$allowed) { throw "File outside approved edit scope: $f" }
        }
        $state.changedFiles = $changedThisTask
        if (!(Test-Path -LiteralPath $resultPath -PathType Leaf)) { throw 'No structured result.json from agent.' }
        $result = Read-JsonFile $resultPath
        if ($result.ticketId -ne $Task.id -or $result.status -notin @('completed','blocked')) { throw 'Invalid agent result contract.' }
        if (!$result.PSObject.Properties['summary'] -or !([string]$result.summary).Trim() -or
            !$result.PSObject.Properties['blockers']) { throw 'Agent result is missing summary/blockers.' }
        if ($result.status -eq 'completed' -and @($result.blockers).Count -gt 0) { throw 'Agent reported completed with unresolved blockers.' }
        Write-JsonFile (Join-Path $outDir 'agent-result.json') $result
        if ($result.status -eq 'blocked') {
            $state.status = 'blocked'; $state.message = [string]$result.summary
        } else {
            if ((Get-Hash $docPath) -eq $docHash) { throw 'Ticket document was not updated.' }
            if ($Task.mode -eq 'implement') {
                if (!$verifierHash -or (Get-Hash $verifier) -ne $verifierHash) { throw 'Verification script missing or changed.' }
                if ([DateTime]::UtcNow -ge $DeadlineUtc -or (Test-Path -LiteralPath $Config.stopFile)) { throw 'Stopped before verification.' }
                $verifyRequest = [ordered]@{
                    kind='verify'; workingDirectory=$root; script=$verifier
                    ticketId=$Task.id; extraPath=$Config.extraPath
                }
                $verify = Invoke-TimedWorker $verifyRequest (Join-Path $outDir 'verification') ([int]($Config.verificationTimeoutMinutes * 60)) $DeadlineUtc $Config.stopFile
                if ($verify.reason -ne 'exited' -or $verify.exitCode -ne 0) {
                    throw "Verification: $($verify.reason), exit=$($verify.exitCode)"
                }
                Assert-Worktree $Project
                if ((Invoke-Git $root @('rev-parse','HEAD')) -ne $head -or (Get-Hash $queuePath) -ne $queueHash) {
                    throw 'Verification changed HEAD or queue.'
                }
                $note = "`n`n## Nightly verification`n- UTC: $([DateTime]::UtcNow.ToString('o'))`n- Script: $($Project.verificationScript)`n- Exit code: 0`n- Logs: $outDir`n- Human review: pending`n"
                Write-Utf8 $docPath ((Get-Content -LiteralPath $docPath -Raw -Encoding UTF8) + $note)
            }
            $state.status = 'ready-for-review'; $state.message = [string]$result.summary
        }
    } catch {
        $state.status = 'failed'; $state.message = $_.Exception.Message
    } finally {
        $state.finishedUtc = [DateTime]::UtcNow.ToString('o')
        # Do not overwrite an independently modified queue after a conflict.
        if ((Get-Hash $queuePath) -eq $queueHash) {
            Set-QueueStatus $queuePath $Task.id $state.status
        } else { $state.status='failed'; $state.message += ' Queue conflict: status not overwritten.' }
        Write-JsonFile (Join-Path $outDir 'state.json') $state
        Write-Utf8 (Join-Path $outDir 'status.txt') (Get-WorkStatus $root)
        Write-Utf8 (Join-Path $outDir 'cumulative.diff') (Invoke-Git $root @('diff','HEAD','--','.',':(exclude).ai-night-run'))
        Write-Utf8 (Join-Path $outDir 'untracked-files.txt') (Invoke-Git $root @('ls-files','--others','--exclude-standard','--','.',':(exclude).ai-night-run'))
    }
    [pscustomobject]$state
}
