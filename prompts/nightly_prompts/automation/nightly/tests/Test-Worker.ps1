#Requires -Version 5.1
# Windows integration smoke test for the wrapper, using a local mock CLI.
# It does not invoke OpenCode or any model. Fixtures are retained for inspection.
. "$PSScriptRoot\..\Common.ps1"
if ($env:OS -ne 'Windows_NT') { throw 'Run on Windows.' }
$root = Join-Path ([IO.Path]::GetTempPath()) ('ai-fosql-worker-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$mock = Join-Path $root 'mock.cmd'
Write-Utf8 $mock "@echo off`r`necho mock-output`r`nexit /b 7`r`n"
$request = @{
    kind='opencode'; executable=$mock; arguments=@(); workingDirectory=$root
    extraPath=@(); inlineConfig=@{ share='disabled' }
}
$r = Invoke-TimedWorker $request (Join-Path $root 'exit-test') 10 ([DateTime]::UtcNow.AddMinutes(1)) (Join-Path $root 'STOP')
if ($r.exitCode -ne 7 -or $r.reason -ne 'exited') { throw 'Exit-code propagation failed.' }
Write-Host 'PASS: native nonzero exit code propagated.'
Write-Utf8 $mock "@echo off`r`nping -n 30 127.0.0.1 >nul`r`n"
$r = Invoke-TimedWorker $request (Join-Path $root 'timeout-test') 1 ([DateTime]::UtcNow.AddMinutes(1)) (Join-Path $root 'STOP')
if ($r.reason -ne 'timeout') { throw 'Timeout test failed.' }
Write-Host 'PASS: timeout stopped mock process tree.'
Write-Utf8 (Join-Path $root 'STOP') 'stop'
$r = Invoke-TimedWorker $request (Join-Path $root 'stop-test') 10 ([DateTime]::UtcNow.AddMinutes(1)) (Join-Path $root 'STOP')
if ($r.reason -ne 'stop-file') { throw 'STOP-file test failed.' }
Write-Host "PASS: STOP file. Fixtures: $root"
