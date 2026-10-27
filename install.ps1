#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$rulePrefix = 'BYTESPOKE -'
$backupRoot = Join-Path $env:ProgramData 'BytespokeFirewallRecovery'
$activePath = Join-Path $backupRoot 'active-install.txt'
$state = $null
if (Test-Path -LiteralPath $activePath) {
    Write-Host 'An installation or unfinished recovery exists. Run uninstall.bat first.'
    exit 1
}
$runName = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N')
$dataDirectory = Join-Path $backupRoot $runName
New-Item -Path $dataDirectory -ItemType Directory -Force | Out-Null
$backupPath = Join-Path $dataDirectory 'pre-install-firewall.wfw'
$statePath = Join-Path $dataDirectory 'install-state.json'
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
    'cloudphone.tatateleservices.com',
    'login.microsoftonline.com', '*.microsoftonline.com',
    'login.microsoftonline-p.com', '*.microsoftonline-p.com',
    'login.microsoft.com', 'login.windows.net',
    'autologon.microsoftazuread-sso.com',
    'aadcdn.msauth.net', '*.msauth.net',
    'aadcdn.msftauth.net', '*.msftauth.net',
    '*.msauthimages.net', '*.msftauthimages.net',
    '*.auth.microsoft.com', '*.msftidentity.com', '*.msidentity.com',
    '*.msecnd.net', '*.phonefactor.net', '*.hip.live.com',
    'recaptcha.net', '*.recaptcha.net',
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
    Write-Host ''
    Write-Host '=========================================='
    Write-Host ' BYTESPOKE - INTERNET ACCESS CONTROL'
    Write-Host '=========================================='
    Write-Host ''

    $requiredCommands = @(
        'New-NetFirewallRule',
        'Get-NetFirewallRule',
        'New-NetFirewallDynamicKeywordAddress',
        'Get-NetFirewallDynamicKeywordAddress',
        'Remove-NetFirewallDynamicKeywordAddress'
    )

    foreach ($command in $requiredCommands) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "Required Windows command is unavailable: $command"
        }
    }

    Write-Host '[1/8] Saving the CURRENT firewall configuration...'
    Write-Warning 'This saves current settings, including old BYTESPOKE rules. It cannot recover the lost original settings.'
    & netsh.exe advfirewall export $backupPath | Out-Host
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $backupPath)) {
        throw 'Could not save current firewall settings. Installation stopped.'
    }
    $preference = Get-MpPreference
    $policyState = @()
    foreach ($browser in $browserPolicies) {
        $policyState += Get-RegistryValueState -Path $browser.Path -Name 'DnsOverHttpsMode'
    }
    $state = [ordered]@{
        PreviousNetworkProtection = [int]$preference.EnableNetworkProtection
        BrowserPolicyState = $policyState
        CreatedDynamicIds = @()
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
    Set-Content -LiteralPath $activePath -Value $dataDirectory -Encoding UTF8
    Write-Host "Backup saved: $backupPath"
    Write-Host ''
    Write-Host '[2/8] Checking Microsoft Defender requirements...'

    $defenderStatus = Get-MpComputerStatus
    if (-not $defenderStatus.AntivirusEnabled) {
        throw 'Microsoft Defender Antivirus must be enabled for Windows FQDN firewall rules.'
    }

    if ((Get-MpPreference).EnableNetworkProtection -eq 0) {
        Set-MpPreference -EnableNetworkProtection AuditMode
    }

    if ((Get-MpPreference).EnableNetworkProtection -eq 0) {
        throw 'Microsoft Defender Network Protection could not be enabled.'
    }

    Write-Host ''
    Write-Host '[3/8] Disabling Secure DNS in Chrome and Edge policy...'

    foreach ($browser in $browserPolicies) {
        if (-not (Test-Path -LiteralPath $browser.Path)) {
            New-Item -Path $browser.Path -Force | Out-Null
        }

        New-ItemProperty `
            -Path $browser.Path `
            -Name 'DnsOverHttpsMode' `
            -Value 'off' `
            -PropertyType String `
            -Force | Out-Null
    }

    Write-Host ''
    Write-Host '[4/8] Enabling Windows Firewall without blocking outbound traffic yet...'

    Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True

    Write-Host ''
    Write-Host '[5/8] Creating DNS and permitted-domain rules...'

    Remove-BytespokeRules

    New-NetFirewallRule `
        -DisplayName "$rulePrefix Allow DNS UDP" `
        -Direction Outbound `
        -Action Allow `
        -Protocol UDP `
        -RemotePort 53 `
        -Profile Any | Out-Null

    New-NetFirewallRule `
        -DisplayName "$rulePrefix Allow DNS TCP" `
        -Direction Outbound `
        -Action Allow `
        -Protocol TCP `
        -RemotePort 53 `
        -Profile Any | Out-Null

    foreach ($domain in $domains) {
        $entry = Get-NetFirewallDynamicKeywordAddress -ErrorAction Stop |
            Where-Object Keyword -EQ $domain |
            Select-Object -First 1

        if (-not $entry) {
            $id = '{' + ([guid]::NewGuid().ToString()) + '}'
            $entry = New-NetFirewallDynamicKeywordAddress `
                -Id $id `
                -Keyword $domain `
                -AutoResolve $true

            if ($state.CreatedDynamicIds -notcontains $id) {
                $state.CreatedDynamicIds += $id
                $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $statePath -Encoding UTF8
            }
        }

        New-NetFirewallRule `
            -DisplayName "$rulePrefix Allow TCP $domain" `
            -Direction Outbound `
            -Action Allow `
            -Protocol TCP `
            -RemotePort 80,443 `
            -RemoteDynamicKeywordAddresses $entry.Id `
            -Profile Any | Out-Null

        New-NetFirewallRule `
            -DisplayName "$rulePrefix Allow QUIC $domain" `
            -Direction Outbound `
            -Action Allow `
            -Protocol UDP `
            -RemotePort 443 `
            -RemoteDynamicKeywordAddresses $entry.Id `
            -Profile Any | Out-Null

        Write-Host "Configured: $domain"
    }

    Write-Host ''
    Write-Host '[6/8] Resolving and validating permitted domains...'

    $exactDomains = @($domains | Where-Object { -not $_.StartsWith('*') })

    foreach ($domain in $exactDomains) {
        try {
            Resolve-DnsName -Name $domain -DnsOnly -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Warning "DNS lookup failed: $domain"
        }
    }

    Start-Sleep -Seconds 5

    $resolvedDomains = @()
    $unresolvedDomains = @()

    foreach ($domain in $exactDomains) {
        $entry = Get-NetFirewallDynamicKeywordAddress |
            Where-Object Keyword -EQ $domain |
            Select-Object -First 1

        if ($entry -and -not [string]::IsNullOrWhiteSpace([string]$entry.Addresses)) {
            $resolvedDomains += $domain
        }
        else {
            $unresolvedDomains += $domain
        }
    }

    if ($resolvedDomains.Count -eq 0) {
        throw 'No permitted domain received a resolved firewall address. Outbound blocking was not applied.'
    }

    if ($unresolvedDomains.Count -gt 0) {
        Write-Host ''
        Write-Warning 'These domains did not currently resolve and will remain unavailable:'
        $unresolvedDomains | ForEach-Object { Write-Host " - $_" }
    }

    Write-Host ''
    Write-Host '[7/8] Setting default inbound and outbound actions to Block...'

    Set-NetFirewallProfile `
        -Profile Domain,Private,Public `
        -DefaultInboundAction Block `
        -DefaultOutboundAction Block

    Write-Host ''
    Write-Host '[8/8] Testing permitted HTTPS access...'

    $testDomains = @('google.com', 'chatgpt.com', 'gofinqo.com')
    $successfulTests = 0

    foreach ($domain in $testDomains) {
        $client = $null

        try {
            $client = [System.Net.Sockets.TcpClient]::new()
            $connected = $client.ConnectAsync($domain, 443).Wait(8000)

            if ($connected -and $client.Connected) {
                Write-Host "Passed: $domain" -ForegroundColor Green
                $successfulTests++
            }
            else {
                Write-Warning "Failed: $domain"
            }
        }
        catch {
            Write-Warning "Failed: $domain"
        }
        finally {
            if ($null -ne $client) {
                $client.Dispose()
            }
        }
    }

    if ($successfulTests -eq 0) {
        throw 'All permitted HTTPS tests failed.'
    }

    Write-Host ''
    Write-Host '=========================================='
    Write-Host ' Firewall configuration completed'
    Write-Host '=========================================='
    Write-Host ''
    Write-Host "Pre-install backup: $backupPath"
    Write-Host 'Run uninstall.bat as administrator to restore pre-install settings.'
    Write-Warning 'Unrelated existing allow rules remain active. This is not a strict website-only filter.'
    Write-Host 'Close and reopen Chrome or Edge before testing websites.'
    Write-Host 'A website may require additional CDN, login, CAPTCHA or payment domains.'
}
catch {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red

    if ($null -ne $state) {
        try {
            Restore-OriginalConfiguration -State $state
            Remove-Item -LiteralPath $activePath -ErrorAction SilentlyContinue
            Write-Host 'Pre-install settings restored.'
        }
        catch {
            Write-Host "Recovery incomplete: $($_.Exception.Message). Run uninstall.bat to retry." -ForegroundColor Red
        }
    }

    exit 1
}
