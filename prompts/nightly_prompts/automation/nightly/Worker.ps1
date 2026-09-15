param([Parameter(Mandatory=$true)][string]$RequestPath)
$ErrorActionPreference = 'Stop'
try {
    $request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Set-Location -LiteralPath $request.workingDirectory
    $utf8 = New-Object Text.UTF8Encoding($false)
    [Console]::OutputEncoding = $utf8; $OutputEncoding = $utf8
    $env:PATH = (@($request.extraPath) -join ';') + ';' + $env:PATH
    if ($request.kind -eq 'opencode') {
        $env:OPENCODE_CONFIG_CONTENT = $request.inlineConfig | ConvertTo-Json -Depth 30 -Compress
        $env:OPENCODE_DISABLE_AUTOUPDATE = 'true'
        $arguments = @($request.arguments | ForEach-Object { [string]$_ })
        $ErrorActionPreference = 'Continue'; $global:LASTEXITCODE = 0
        & $request.executable @arguments
        exit $LASTEXITCODE
    } elseif ($request.kind -eq 'verify') {
        $global:LASTEXITCODE = 0
        & $request.script -ProjectPath $request.workingDirectory -TicketId $request.ticketId
        if (!$?) { exit 1 }
        exit $LASTEXITCODE
    } else { throw 'Unknown worker request kind.' }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
