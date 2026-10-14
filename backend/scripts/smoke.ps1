param([string]$BaseUrl = 'http://127.0.0.1:18080')
$ErrorActionPreference = 'Stop'
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$csrf = Invoke-RestMethod -Uri "$BaseUrl/api/auth/csrf" -WebSession $session
$headers = @{ 'X-CSRF-TOKEN' = $csrf.token }

function Call-Api {
    param([string]$Method, [string]$Path, $Body = $null)
    $params = @{
        Uri = "$BaseUrl/api$Path"
        Method = $Method
        WebSession = $session
        Headers = $headers
        ContentType = 'application/json'
    }
    if ($null -ne $Body) { $params.Body = $Body | ConvertTo-Json -Depth 10 -Compress }
    return Invoke-RestMethod @params
}

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 10)
$identity = Call-Api 'POST' '/auth/register' @{
    loginName = "smoke_$suffix"
    password = 'smoke-password-123'
    workspaceName = "Smoke $suffix"
}
$wid = $identity.workspaces[0].workspaceId
if (-not $wid) { throw 'Registration did not return a workspace' }
$pet = Call-Api 'POST' "/workspaces/$wid/pets" @{
    name = 'Test Cat'; species = '猫'; sex = 'UNKNOWN'; status = 'ACTIVE'
}
$device = Call-Api 'POST' "/workspaces/$wid/devices" @{
    name = 'Test Scale'; serialNumber = "scale-$suffix"; kind = 'SCALE'; sharingPolicy = 'DEDICATED'
}
Call-Api 'PUT' "/workspaces/$wid/pets/$($pet.id)" @{
    name = 'Test Cat'; species = '猫'; breed = 'Mixed'; sex = 'UNKNOWN'; status = 'ACTIVE'
} | Out-Null
Call-Api 'PUT' "/workspaces/$wid/devices/$($device.id)" @{
    name = 'Updated Scale'; spaceId = $null
} | Out-Null
if ((Call-Api 'GET' "/workspaces/$wid/pets/$($pet.id)").breed -ne 'Mixed') {
    throw 'Pet update failed'
}
if ((Call-Api 'GET' "/workspaces/$wid/devices/$($device.id)").name -ne 'Updated Scale') {
    throw 'Device update failed'
}
Call-Api 'POST' "/workspaces/$wid/devices/$($device.id)/status" @{ status = 'ONLINE' } | Out-Null
Call-Api 'POST' "/workspaces/$wid/devices/$($device.id)/bindings" @{ petId = $pet.id } | Out-Null
$rule = Call-Api 'POST' "/workspaces/$wid/rules" @{
    name = 'Weight alert'; metricCode = 'weight_kg'; comparator = 'GT'; threshold = 3
    actionKind = 'ALERT'; actionPayload = @{}; severity = 'WARNING'; cooldownSeconds = 0
}
$measurement = Call-Api 'POST' "/workspaces/$wid/measurements" @{
    sourceKind = 'DEVICE'; deviceId = $device.id; sourceEventId = "event-$suffix"
    metricCode = 'weight_kg'; value = 4.2
    measuredAt = (Get-Date).ToUniversalTime().ToString('o')
}
$measurements = Call-Api 'GET' "/workspaces/$wid/measurements"
$alerts = Call-Api 'GET' "/workspaces/$wid/alerts"
$executions = Call-Api 'GET' "/workspaces/$wid/executions"
if ($measurements[0].id -ne $measurement.id -or $measurements[0].petId -ne $pet.id -or
    $measurements[0].attributionMethod -ne 'BINDING') { throw 'Measurement attribution failed' }
if ($alerts.Count -lt 1 -or $alerts[0].title -ne 'Weight alert') { throw 'Rule did not create alert' }
if ($executions.Count -lt 1 -or $executions[0].status -ne 'SUCCEEDED') { throw 'Automation did not succeed' }
Call-Api 'POST' "/workspaces/$wid/alerts/$($alerts[0].id)/resolve" | Out-Null
$updated = Call-Api 'GET' "/workspaces/$wid/alerts"
if ($updated[0].status -ne 'RESOLVED') { throw 'Alert resolution failed' }
$commandRule = Call-Api 'POST' "/workspaces/$wid/rules" @{
    name = 'Scale ping'; metricCode = 'weight_kg'; comparator = 'GT'; threshold = 3
    actionKind = 'DEVICE_COMMAND'; targetDeviceId = $device.id
    actionPayload = @{ command_type = 'PING' }; severity = 'INFO'; cooldownSeconds = 0
}
$second = Call-Api 'POST' "/workspaces/$wid/measurements" @{
    sourceKind = 'DEVICE'; deviceId = $device.id; sourceEventId = "event2-$suffix"
    metricCode = 'weight_kg'; value = 4.3
    measuredAt = (Get-Date).ToUniversalTime().ToString('o')
}
$commands = Call-Api 'GET' "/workspaces/$wid/devices/$($device.id)/commands"
if ($commands.Count -lt 1 -or $commands[0].status -ne 'APPLIED' -or
    $commands[0].commandType -ne 'PING') { throw 'Automated simulated command failed' }

$shared = Call-Api 'POST' "/workspaces/$wid/devices" @{
    name = 'Shared Scale'; serialNumber = "shared-$suffix"; kind = 'SCALE'; sharingPolicy = 'SHARED'
}
Call-Api 'POST' "/workspaces/$wid/devices/$($shared.id)/bindings" @{ petId = $pet.id } | Out-Null
$unknown = Call-Api 'POST' "/workspaces/$wid/measurements" @{
    sourceKind = 'DEVICE'; deviceId = $shared.id; sourceEventId = "shared-event-$suffix"
    metricCode = 'weight_kg'; value = 4.4
    measuredAt = (Get-Date).ToUniversalTime().ToString('o')
}
$current = Call-Api 'GET' "/workspaces/$wid/measurements"
if ($current[0].id -ne $unknown.id -or $null -ne $current[0].petId -or
    $current[0].attributionMethod -ne 'UNKNOWN') { throw 'Shared device was incorrectly attributed' }
Call-Api 'POST' "/workspaces/$wid/measurements/$($unknown.id)/attributions" @{
    petId = $pet.id; reason = 'Manual identity confirmation during smoke test'
} | Out-Null
$current = Call-Api 'GET' "/workspaces/$wid/measurements"
if ($current[0].petId -ne $pet.id -or $current[0].attributionMethod -ne 'IDENTIFIED') {
    throw 'Attribution revision failed'
}
$report = Call-Api 'GET' "/workspaces/$wid/pets/$($pet.id)/report"
if ($report.latestWeight.weightKg -ne 4.4) { throw 'SQL health report has wrong latest weight' }
try {
    Call-Api 'POST' "/workspaces/$wid/ai/assistant" @{ question = 'Is this a real model?' } | Out-Null
    throw 'AI placeholder pretended to respond'
} catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 501) { throw }
}
try {
    Call-Api 'POST' "/workspaces/$wid/measurements" @{
        sourceKind = 'DEVICE'; deviceId = $shared.id; sourceEventId = "shared-event-$suffix"
        metricCode = 'weight_kg'; value = 4.5
        measuredAt = (Get-Date).ToUniversalTime().ToString('o')
    } | Out-Null
    throw 'Duplicate device event was accepted'
} catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 409) { throw }
}

$otherSession = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$otherCsrf = Invoke-RestMethod -Uri "$BaseUrl/api/auth/csrf" -WebSession $otherSession
$otherHeaders = @{ 'X-CSRF-TOKEN' = $otherCsrf.token }
$otherBody = @{
    loginName = "other_$suffix"; password = 'smoke-password-123'; workspaceName = "Other $suffix"
} | ConvertTo-Json -Compress
Invoke-RestMethod -Uri "$BaseUrl/api/auth/register" -Method Post -WebSession $otherSession `
    -Headers $otherHeaders -ContentType 'application/json' -Body $otherBody | Out-Null
try {
    Invoke-RestMethod -Uri "$BaseUrl/api/workspaces/$wid/pets" -WebSession $otherSession | Out-Null
    throw 'Cross-workspace request was not blocked'
} catch {
    if ($_.Exception.Response.StatusCode.value__ -ne 403) { throw }
}
Write-Output "PASS workspace=$wid pet=$($pet.id) devices=$($device.id),$($shared.id) rules=$($rule.id),$($commandRule.id) measurements=$($measurement.id),$($second.id),$($unknown.id)"
