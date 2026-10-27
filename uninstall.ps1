#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$rulePrefix = 'BYTESPOKE -'
$backupRoot = Join-Path $env:ProgramData 'BytespokeFirewallRecovery'
$activePath = Join-Path $backupRoot 'active-install.txt'
$domains = @(
    'gofinqo.com', '*.gofinqo.com',
    'google.com', '*.google.com',
    'gstatic.com', '*.gstatic.com',
    'googleapis.com', '*.googleapis.com',
    'googleusercontent.com', '*.googleusercontent.com',
    'bank.in', '*.bank.in',
    'au.bank.in', '*.au.bank.in',
    'idfcfirst.bank.in', '*.idfcfirst.bank.in',
    'icici.bank.in', 'www.icici.bank.in', '*.icici.bank.in',
    'retailnetbanking.icici.bank.in',
    'services.icici.bank.in',
    'buy.icici.bank.in',
    'nli.icici.bank.in',
    'www.giftcity.icici.bank.in',
    'muthootfincorp.com', '*.muthootfincorp.com',
    'tatacapital.com', '*.tatacapital.com',
    'nivabupa.com', '*.nivabupa.com',
    'tataaig.com', '*.tataaig.com',
    'adityabirlahealthinsurance.com', '*.adityabirlahealthinsurance.com',
    'axismaxlife.com', '*.axismaxlife.com',
    'snnetworkinsurance.com', '*.snnetworkinsurance.com',
    'chatgpt.com', '*.chatgpt.com',
    'openai.com', '*.openai.com',
    'oaistatic.com', '*.oaistatic.com',
    'oaiusercontent.com', '*.oaiusercontent.com',
    'challenges.cloudflare.com'
)

$browserPolicies = @(
    @{ Name = 'Chrome'; Path = 'HKLM:\SOFTWARE\Policies\Google\Chrome' },
    @{ Name = 'Edge'; Path = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' }
)

function Get-RegistryValueState {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name
    )

    $keyExisted = Test-Path -LiteralPath $Path
    $valueExisted = $false
    $value = $null

    if ($keyExisted) {
        $property = Get-ItemProperty -LiteralPath $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $property) {
            $valueExisted = $true
            $value = $property.$Name
        }
    }

    return [ordered]@{
        Path         = $Path
        Name         = $Name
        KeyExisted   = $keyExisted
        ValueExisted = $valueExisted
        Value        = $value
    }
}

function Remove-BytespokeRules {
    Get-NetFirewallRule -ErrorAction SilentlyContinue |
        Where-Object DisplayName -Like "$rulePrefix*" |
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

function Remove-CreatedDynamicAddresses {
    param([string[]] $Ids)

    foreach ($id in @($Ids)) {
        if ([string]::IsNullOrWhiteSpace($id)) {
            continue
        }

        Get-NetFirewallDynamicKeywordAddress -Id $id -ErrorAction SilentlyContinue |
            Remove-NetFirewallDynamicKeywordAddress -ErrorAction SilentlyContinue
    }
}

function Restore-OriginalConfiguration {
    param($State)

    Write-Host ''
    Write-Host 'Restoring the saved pre-install configuration...' -ForegroundColor Yellow

    if (-not (Test-Path -LiteralPath $backupPath)) { throw 'Firewall backup is missing.' }
    & netsh.exe advfirewall import $backupPath | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Firewall restoration failed. Backup files retained.' }
    foreach ($id in @($State.CreatedDynamicIds)) {
        if (Get-NetFirewallDynamicKeywordAddress -Id $id -ErrorAction SilentlyContinue) {
            Remove-NetFirewallDynamicKeywordAddress -Id $id -ErrorAction Stop
        }
    }

    if ($null -ne $State.PreviousNetworkProtection) {
        switch ([int]$State.PreviousNetworkProtection) {
            0 { Set-MpPreference -EnableNetworkProtection Disabled }
            1 { Set-MpPreference -EnableNetworkProtection Enabled }
            2 { Set-MpPreference -EnableNetworkProtection AuditMode }
        }
    }

    foreach ($registryState in @($State.BrowserPolicyState)) {
        if ($registryState.ValueExisted) {
            if (-not (Test-Path -LiteralPath $registryState.Path)) {
                New-Item -Path $registryState.Path -Force | Out-Null
            }

            New-ItemProperty `
                -Path $registryState.Path `
                -Name $registryState.Name `
                -Value $registryState.Value `
                -PropertyType String `
                -Force | Out-Null
        }
        else {
            Remove-ItemProperty `
                -LiteralPath $registryState.Path `
                -Name $registryState.Name `
                -ErrorAction SilentlyContinue
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $activePath)) {
        Write-Host 'No installation from this version is recorded. No settings were changed.'
        exit 0
    }
    $dataDirectory = (Get-Content -LiteralPath $activePath -Raw).Trim()
    $root = [IO.Path]::GetFullPath($backupRoot).TrimEnd('\') + '\'
    if (-not [IO.Path]::GetFullPath($dataDirectory).StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Invalid backup location.'
    }
    $backupPath = Join-Path $dataDirectory 'pre-install-firewall.wfw'
    $statePath = Join-Path $dataDirectory 'install-state.json'
    if (-not (Test-Path -LiteralPath $backupPath) -or -not (Test-Path -LiteralPath $statePath)) {
        throw 'Required backup files are missing. No settings were changed.'
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $safetyPath = Join-Path $dataDirectory ('before-uninstall-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.wfw')
    & netsh.exe advfirewall export $safetyPath | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'Could not save current firewall before restoration.' }
    Restore-OriginalConfiguration -State $state
    Remove-Item -LiteralPath $activePath -ErrorAction Stop
    Write-Host 'Uninstall completed. Pre-install settings restored.' -ForegroundColor Green
    Write-Host 'Older BYTESPOKE rules in that backup are restored too.'
    Write-Host "Backups retained: $dataDirectory"
    Write-Host 'Close and reopen Chrome and Edge.'
}
catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Backups and the installation record are retained for recovery.'
    exit 1
}