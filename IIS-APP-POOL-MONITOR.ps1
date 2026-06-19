[CmdletBinding()]
param(
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$logPath = 'C:\Logs\iis-monitor.log'
$logDir = Split-Path -Path $logPath -Parent

if (-not (Test-Path -Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = '{0} [{1}] {2}' -f $timestamp, $Level, $Message
    Add-Content -Path $logPath -Value $line
    Write-Output $line
}

try {
    Import-Module WebAdministration -ErrorAction Stop
    Write-Log 'Loaded WebAdministration module.'
}
catch {
    Write-Log ("Failed to load WebAdministration module. Error: {0}" -f $_.Exception.Message) 'ERROR'
    throw
}

$script:StopMonitoring = $false
$script:rollbackInvoked = $false
$script:initialPoolStates = @{}
$script:monitorMutex = $null
$script:ownsMonitorMutex = $false

function Acquire-MonitorMutex {
    try {
        $script:monitorMutex = [System.Threading.Mutex]::new($false, 'Global\IisAppPoolMonitor')
        $script:ownsMonitorMutex = $script:monitorMutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        $script:ownsMonitorMutex = $true
        Write-Log 'Recovered an abandoned monitor mutex; continuing as the active instance.' 'WARN'
    }
    catch {
        Write-Log ("Failed to acquire monitor mutex. Error: {0}" -f $_.Exception.Message) 'ERROR'
        throw
    }

    if (-not $script:ownsMonitorMutex) {
        Write-Log 'Another IIS app pool monitor instance is already running. Exiting for idempotency.' 'WARN'
        exit 0
    }

    Write-Log 'Acquired single-instance monitor mutex.'
}

function Release-MonitorMutex {
    if ($script:monitorMutex -is [System.Threading.Mutex]) {
        try {
            if ($script:ownsMonitorMutex) {
                $script:monitorMutex.ReleaseMutex()
                Write-Log 'Released single-instance monitor mutex.'
            }
        }
        catch {
            Write-Log ("Failed to release monitor mutex cleanly. Error: {0}" -f $_.Exception.Message) 'ERROR'
        }
        finally {
            $script:monitorMutex.Dispose()
            $script:monitorMutex = $null
            $script:ownsMonitorMutex = $false
        }
    }
}

function Invoke-Rollback {
    if ($script:rollbackInvoked) {
        Write-Log 'Rollback already executed. Skipping duplicate rollback request.'
        return
    }

    $script:rollbackInvoked = $true
    $script:StopMonitoring = $true
    Write-Log 'Rollback started: stopping monitor loop and restoring initial app pool states.' 'WARN'

    foreach ($poolName in $script:initialPoolStates.Keys) {
        $targetState = $script:initialPoolStates[$poolName]

        try {
            $currentState = (Get-WebAppPoolState -Name $poolName -ErrorAction Stop).Value
            if ($targetState -eq 'Started') {
                if ($currentState -ne 'Started') {
                    if ($DryRun) {
                        Write-Log ("[DryRun] Would start app pool '{0}' during rollback." -f $poolName)
                    }
                    else {
                        Start-WebAppPool -Name $poolName -ErrorAction Stop
                        Write-Log ("Rollback: started app pool '{0}' to restore initial Started state." -f $poolName)
                    }
                }
                else {
                    Write-Log ("Rollback: app pool '{0}' already Started; no action needed." -f $poolName)
                }
            }
            elseif ($targetState -eq 'Stopped') {
                if ($currentState -ne 'Stopped') {
                    if ($DryRun) {
                        Write-Log ("[DryRun] Would stop app pool '{0}' during rollback." -f $poolName)
                    }
                    else {
                        Stop-WebAppPool -Name $poolName -ErrorAction Stop
                        Write-Log ("Rollback: stopped app pool '{0}' to restore initial Stopped state." -f $poolName)
                    }
                }
                else {
                    Write-Log ("Rollback: app pool '{0}' already Stopped; no action needed." -f $poolName)
                }
            }
            else {
                Write-Log ("Rollback: unsupported target state '{0}' for app pool '{1}'." -f $targetState, $poolName) 'WARN'
            }
        }
        catch {
            Write-Log ("Rollback failed for app pool '{0}'. Error: {1}" -f $poolName, $_.Exception.Message) 'ERROR'
        }
    }

    Write-Log 'Rollback completed.' 'WARN'
}

try {
    $appPools = Get-ChildItem IIS:\AppPools -ErrorAction Stop
    foreach ($pool in $appPools) {
        try {
            $state = (Get-WebAppPoolState -Name $pool.Name -ErrorAction Stop).Value
            $script:initialPoolStates[$pool.Name] = $state
        }
        catch {
            Write-Log ("Failed to read initial state for app pool '{0}'. Error: {1}" -f $pool.Name, $_.Exception.Message) 'ERROR'
        }
    }

    Write-Log ("Captured initial app pool states for {0} pools." -f $script:initialPoolStates.Count)
}
catch {
    Write-Log ("Failed to enumerate IIS app pools. Error: {0}" -f $_.Exception.Message) 'ERROR'
    throw
}

Acquire-MonitorMutex

$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    if (-not $script:rollbackInvoked) {
        Write-Log 'PowerShell exiting event received. Executing rollback and shutting down monitor loop.' 'WARN'
        Invoke-Rollback
    }
} -SupportEvent

Write-Log ("IIS app pool monitoring started. Interval: 60 seconds. DryRun: {0}" -f $DryRun)

try {
    while (-not $script:StopMonitoring) {
        try {
            $pools = Get-ChildItem IIS:\AppPools -ErrorAction Stop
        }
        catch {
            Write-Log ("Failed to enumerate IIS app pools in monitor loop. Error: {0}" -f $_.Exception.Message) 'ERROR'
            Start-Sleep -Seconds 60
            continue
        }

        foreach ($pool in $pools) {
            $poolName = $pool.Name
            $poolState = $null

            try {
                $poolState = (Get-WebAppPoolState -Name $poolName -ErrorAction Stop).Value
            }
            catch {
                Write-Log ("Failed to get state for app pool '{0}'. Error: {1}" -f $poolName, $_.Exception.Message) 'ERROR'
                continue
            }

            if ($poolState -eq 'Stopped') {
                Write-Log ("Detected Stopped app pool '{0}'. Capturing Windows Event Log errors from last 10 minutes." -f $poolName) 'WARN'

                try {
                    $startTime = (Get-Date).AddMinutes(-10)
                    $events = Get-WinEvent -FilterHashtable @{
                        LogName   = @('Application', 'System')
                        StartTime = $startTime
                        Level     = 2
                    } -ErrorAction Stop

                    if ($events) {
                        foreach ($logEvent in $events) {
                            $eventMessage = ([string]$logEvent.Message).Replace([Environment]::NewLine, ' ')
                            $eventText = "EventId={0}; Log={1}; Provider={2}; Time={3}; Message={4}" -f $logEvent.Id, $logEvent.LogName, $logEvent.ProviderName, $logEvent.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss'), $eventMessage
                            Write-Log $eventText 'ERROR'
                        }
                    }
                    else {
                        Write-Log 'No error events found in Application/System logs for the last 10 minutes.'
                    }
                }
                catch {
                    Write-Log ("Failed to capture Event Log errors. Error: {0}" -f $_.Exception.Message) 'ERROR'
                }

                try {
                    $currentStateBeforeStart = (Get-WebAppPoolState -Name $poolName -ErrorAction Stop).Value

                    if ($currentStateBeforeStart -eq 'Started') {
                        Write-Log ("Idempotency check: app pool '{0}' is already Started; restart skipped." -f $poolName)
                        continue
                    }

                    if ($DryRun) {
                        Write-Log ("[DryRun] Would restart app pool '{0}' (Start operation because current state is Stopped)." -f $poolName) 'WARN'
                    }
                    else {
                        Start-WebAppPool -Name $poolName -ErrorAction Stop
                        Write-Log ("Restart action completed for app pool '{0}'." -f $poolName) 'WARN'
                    }
                }
                catch {
                    Write-Log ("Failed to restart app pool '{0}'. Error: {1}" -f $poolName, $_.Exception.Message) 'ERROR'
                }
            }
        }

        if (-not $script:StopMonitoring) {
            Start-Sleep -Seconds 60
        }
    }
}
catch [System.Management.Automation.PipelineStoppedException] {
    Write-Log 'Pipeline stopped (Ctrl+C or host interruption detected). Initiating rollback and clean exit.' 'WARN'
    Invoke-Rollback
}
catch {
    Write-Log ("Unexpected error in monitor loop. Error: {0}" -f $_.Exception.Message) 'ERROR'
    Invoke-Rollback
    throw
}
finally {
    Unregister-Event -SourceIdentifier PowerShell.Exiting -ErrorAction SilentlyContinue
    Release-MonitorMutex
    Write-Log 'IIS app pool monitor exited cleanly.'
}
