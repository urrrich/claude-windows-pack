#requires -Version 5.1
[CmdletBinding()]
param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
try {
    if ($PSVersionTable.PSEdition -ne 'Desktop') {
        throw 'Run this script with Windows PowerShell 5.1 (powershell.exe), not pwsh.exe.'
    }
    $packages = @(Get-AppxPackage -Name Claude)
    if ($packages.Count -ne 1) { throw 'Expected one Claude MSIX for the current user. Install Claude using the official Setup first.' }
    $package = $packages[0]
    if ($package.PackageFamilyName -ne 'Claude_pzs8sxrjxfjjc' -or $package.Status -ne 'Ok') {
        throw 'Unexpected Claude package identity or unhealthy package status. Use official Setup to repair it.'
    }
    $manifest = Join-Path $package.InstallLocation 'AppxManifest.xml'
    $binary = Join-Path $package.InstallLocation 'app\resources\cowork-svc.exe'
    if (-not (Test-Path -LiteralPath $manifest -PathType Leaf) -or -not (Test-Path -LiteralPath $binary -PathType Leaf)) {
        throw 'Official service files are missing. Use official Setup to repair Claude.'
    }
    $signature = Get-AuthenticodeSignature -LiteralPath $binary
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?:^|,\s*)O=\u0022Anthropic, PBC\u0022(?:,|$)') {
        throw 'Official Cowork service signature could not be verified. Repair stopped.'
    }
    [xml]$xml = Get-Content -LiteralPath $manifest -Raw
    $declared = @($xml.SelectNodes("//*[local-name()='Extension' and @Category='windows.service']/*[local-name()='Service' and @Name='CoworkVMService']"))
    if ($declared.Count -ne 1) { throw 'This official package does not declare CoworkVMService.' }
    $service = Get-Service -Name CoworkVMService -ErrorAction SilentlyContinue
    Write-Host ('Claude version: ' + $package.Version)
    if ($service) { Write-Host ('Cowork service: ' + $service.Status) }
    else { Write-Host 'Cowork service: MISSING' }
    if ($CheckOnly) { Write-Host 'Check complete. No changes made.'; return }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Open Windows PowerShell as administrator using the SAME Windows account that uses Claude, then run this script again. Do not switch accounts.'
    }
    if (-not $service) {
        if (@(Get-Process -Name Claude -ErrorAction SilentlyContinue).Count -gt 0) {
            throw 'Save your work and fully exit Claude from the system tray, then retry. No processes were stopped.'
        }
        Write-Host 'Restoring official application registration (user data is preserved)...'
        Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop
        $service = Get-Service -Name CoworkVMService -ErrorAction Stop
    }
    $config = Get-CimInstance Win32_Service -Filter "Name='CoworkVMService'"
    $servicePath = ([string]$config.PathName).Trim().Trim('"')
    if (-not [string]::Equals($servicePath, $binary, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Registered service path does not match the verified official package. Repair stopped.'
    }
    if ($service.Status -ne 'Running') { Start-Service -Name CoworkVMService -ErrorAction Stop }
    $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds(30))
    $ready = $false
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        $service.Refresh()
        if ($service.Status -ne 'Running') { throw 'Cowork service stopped during startup. Check C:\ProgramData\Claude\Logs\cowork-service.log.' }
        if ([IO.Directory]::GetFiles('\\.\pipe\') -contains '\\.\pipe\cowork-vm-service') { $ready = $true; break }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'Service is running but its communication pipe is not ready. Check C:\ProgramData\Claude\Logs\cowork-service.log.' }
    Write-Host 'SUCCESS: Cowork service is running and its communication pipe is ready. Reopen Claude and try Cowork.' -ForegroundColor Green
    Write-Host 'This checks service readiness only; it does not test a VM task or change VM/user data.'
} catch {
    Write-Error ('Cowork repair failed: ' + $_.Exception.Message) -ErrorAction Continue
    exit 1
}