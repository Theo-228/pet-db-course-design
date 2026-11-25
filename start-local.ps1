$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$runtime = Join-Path $PSScriptRoot '.local'
New-Item -ItemType Directory -Force $runtime | Out-Null
& D:\pgsql\bin\pg_ctl.exe -D "$runtime\pgdata" status | Out-Null
if ($LASTEXITCODE -ne 0) {
    & D:\pgsql\bin\pg_ctl.exe -D "$runtime\pgdata" -l "$runtime\postgres.log" -o '-p 15432 -h 127.0.0.1' -w start
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL failed to start' }
}
$env:PETOS_DB_URL = 'jdbc:postgresql://127.0.0.1:15432/petos'
$env:PETOS_DB_USER = 'petos'
$env:PETOS_DB_PASSWORD = ''
$env:PETOS_PORT = '18080'
$env:PETOS_API_TARGET = 'http://127.0.0.1:18080'
if (!(Test-NetConnection 127.0.0.1 -Port 18080 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    $backend = Start-Process D:\JDK21\bin\java.exe -ArgumentList '-jar', 'backend\target\petos-backend-0.1.0.jar', '--server.address=127.0.0.1' -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -RedirectStandardOutput "$runtime\backend.log" -RedirectStandardError "$runtime\backend.err.log" -PassThru
    $backend.Id | Set-Content "$runtime\backend.pid"
}
if (!(Test-NetConnection 127.0.0.1 -Port 5173 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    $frontend = Start-Process D:\Nodejs\node.exe -ArgumentList 'node_modules\vite\bin\vite.js', '--host', '127.0.0.1', '--port', '5173', '--strictPort' -WorkingDirectory "$PSScriptRoot\frontend" -WindowStyle Hidden -RedirectStandardOutput "$runtime\frontend.log" -RedirectStandardError "$runtime\frontend.err.log" -PassThru
    $frontend.Id | Set-Content "$runtime\frontend.pid"
}
Write-Host 'PetOS: http://127.0.0.1:5173/ (backend may need a few seconds)'
