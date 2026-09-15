#Requires -Version 5.1
# Offline tests. No OpenCode, model, scheduler or corporate network.
. "$PSScriptRoot\..\Common.ps1"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('ai-fosql-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:passed = 0
function Assert-True([bool]$Condition, [string]$Name) {
    if (!$Condition) { throw "FAIL: $Name" }
    $script:passed++; Write-Host "PASS: $Name"
}
function Assert-Throws([scriptblock]$Action, [string]$Name) {
    $thrown = $false
    try { & $Action | Out-Null } catch { $thrown = $true }
    Assert-True $thrown $Name
}
foreach ($file in (Get-ChildItem -LiteralPath (Split-Path $PSScriptRoot -Parent) -Filter '*.ps1' -Recurse)) {
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) ("parse " + $file.Name + ' ' + ($errors -join '; '))
}
$q = Join-Path $testRoot 'queue.md'
$a = '- [ ] A | mode=implement | status=night-ready | doc=docs/A.md | depends=-'
$b = '- [ ] B | mode=implement | status=night-ready | doc=docs/B.md | depends=A'
Write-Utf8 $q ("# Queue`n`n$a`n$b`n")
$items = @(Read-Queue $q)
Assert-True ($items.Count -eq 2) 'two entries'
Assert-True ((Select-ReadyTask $items $false).id -eq 'A') 'first runnable'
Set-QueueStatus $q 'A' 'ready-for-review'
$items = @(Read-Queue $q)
Assert-True ($null -eq (Select-ReadyTask $items $false)) 'human acceptance required for dependency'
Assert-True ((Select-ReadyTask $items $true).id -eq 'B') 'optional verified implementation dependency'
Assert-True (!(Get-Content $q -Raw).Contains('- [x]')) 'no automatic checked boxes'
Set-QueueStatus $q 'A' 'done'
Assert-True ((Select-ReadyTask @(Read-Queue $q) $false).id -eq 'B') 'accepted dependency'
Write-Utf8 $q "$a`n$a"
Assert-Throws { Read-Queue $q } 'duplicate ID rejected'
Write-Utf8 $q ($a.Replace('depends=-','depends=UNKNOWN'))
Assert-Throws { Read-Queue $q } 'unknown dependency rejected'
Write-Utf8 $q ($a.Replace('depends=-','depends=B') + "`n" + $b)
Assert-Throws { Read-Queue $q } 'dependency cycle rejected'
Write-Utf8 $q ($a.Replace('[ ]','[x]'))
Assert-Throws { Read-Queue $q } 'checkbox/status mismatch rejected'
Write-Utf8 $q '- [ ] Free text is not silently skipped'
Assert-Throws { Read-Queue $q } 'malformed checkbox rejected'
Write-Utf8 $q (($a.Replace('mode=implement','mode=plan').Replace('status=night-ready','status=ready-for-review')) + "`n" + $b)
Assert-True ($null -eq (Select-ReadyTask @(Read-Queue $q) $true)) 'draft plan cannot unblock implementation'
Assert-Throws { Resolve-ProjectFile $testRoot '../outside.txt' } 'path traversal rejected'
Write-JsonFile (Join-Path $testRoot 'array.json') @([pscustomobject]@{ id='A' })
Assert-True ((Get-Content (Join-Path $testRoot 'array.json') -Raw).TrimStart().StartsWith('[')) 'one-item report remains array'
Write-Host "Passed: $script:passed. Temporary fixtures kept at: $testRoot"
