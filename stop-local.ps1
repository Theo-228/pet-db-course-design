$ErrorActionPreference = 'Stop'
foreach ($name in @('frontend', 'backend')) {
    $pidFile = Join-Path $PSScriptRoot ".local\$name.pid"
    if (Test-Path $pidFile) {
        $processId = [int](Get-Content $pidFile)
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$processId"
        if ($process -and ($process.CommandLine -match 'petos-backend-0\.1\.0\.jar|node_modules\\vite\\bin\\vite\.js')) {
            Stop-Process -Id $processId
        }
        Remove-Item -LiteralPath $pidFile
    }
}
& D:\pgsql\bin\pg_ctl.exe -D "$PSScriptRoot\.local\pgdata" -m fast -w stop
