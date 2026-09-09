[CmdletBinding()]
param(
    [string]$SetupPath = (Join-Path $PSScriptRoot '..\build-runtime\Claude Setup.exe'),
    [string]$OutputRoot = (Join-Path $PSScriptRoot '..\releases'),
    [string]$IconPath,
    [string]$MsixUrl = 'https://api.anthropic.com/api/desktop/win32/x64/msix/latest/redirect',
    [switch]$Force,
    [switch]$NoExe,
    [switch]$IncludeCode,
    [switch]$ReuseMsix,
    [switch]$IncludeRuntime,
    [string]$RuntimeRoot = (Join-Path $env:LOCALAPPDATA 'Claude-3p')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'lib\Packaging.Common.ps1')
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
Assert-PlainPath $OutputRoot
if ($IncludeRuntime) { $IncludeCode = $true }
if ($IncludeCode -and $NoExe -and -not $IncludeRuntime) {
    throw '-IncludeCode requires an EXE; use -IncludeRuntime for directory payloads.'
}

function Get-RedirectUrl([string]$Url) {
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    try {
        $response = $client.GetAsync($Url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try {
            if ($response.Headers.Location) {
                return ([Uri]::new([Uri]$Url, $response.Headers.Location)).AbsoluteUri
            }
            $response.EnsureSuccessStatusCode() | Out-Null
            return $Url
        } finally { $response.Dispose() }
    } finally { $client.Dispose() }
}

if (-not (Test-Path -LiteralPath $SetupPath -PathType Leaf)) {
    throw "Setup not found: $SetupPath"
}
$resolved = Get-RedirectUrl $MsixUrl
if ($resolved -notmatch '^https://downloads\.claude\.ai/releases/win32/x64/(\d+\.\d+\.\d+)/[^/]+\.msix$') {
    throw "Unexpected MSIX URL: $resolved"
}
$release = $Matches[1]
$version = "$release.0"
$outDir = Join-Path $OutputRoot "Claude-Desktop-Offline-$release-x64"
if ((Test-Path $outDir) -and -not $Force) { throw "Output exists: $outDir (use -Force to replace files)" }
if ((Test-Path (Join-Path $outDir 'payload')) -or (Test-Path (Join-Path $outDir 'Install-Claude-Full.ps1'))) {
    throw 'A full payload already exists. Use a new -OutputRoot to prevent stale or mixed runtime files.'
}
New-Item -ItemType Directory -Force $outDir | Out-Null

$setupOut = Join-Path $outDir 'Claude Setup.exe'
$msixOut = Join-Path $outDir 'Claude-x64.msix'
Assert-AnthropicSignature $SetupPath
if ([IO.Path]::GetFullPath($SetupPath) -ne $setupOut) {
    Copy-Item -LiteralPath $SetupPath -Destination $setupOut -Force
}
if (-not ($ReuseMsix -and (Test-Path -LiteralPath $msixOut))) {
    Write-Host "Downloading Claude Desktop $version..."
    $partial = "$msixOut.$([guid]::NewGuid().ToString('N')).partial"
    Invoke-WebRequest -UseBasicParsing -Uri $resolved -OutFile $partial
    Assert-AnthropicSignature $partial
    Move-Item -LiteralPath $partial -Destination $msixOut -Force
} else {
    Write-Host "Reusing Claude Desktop $version; signature and manifest will be revalidated."
}

foreach ($file in @($setupOut, $msixOut)) {
    Assert-AnthropicSignature $file
}
$identity = Get-MsixIdentity $msixOut
if ($identity.Name -ne 'Claude' -or $identity.Version -ne $version -or $identity.ProcessorArchitecture -ne 'x64') {
    throw 'MSIX manifest does not match the requested Claude x64 release.'
}
$codeDir = $null
if ($IncludeCode) { $codeDir = Get-CodeRuntime $RuntimeRoot }

$installPs1 = @'
$ErrorActionPreference = 'Stop'
$installer = Join-Path $PSScriptRoot 'Claude Setup.exe'
$msix = Join-Path $PSScriptRoot 'Claude-x64.msix'
if (-not (Test-Path -LiteralPath $installer)) { throw "Claude Setup.exe was not found: $installer" }
if (-not (Test-Path -LiteralPath $msix)) { throw "Claude-x64.msix was not found: $msix" }
foreach ($file in @($installer, $msix)) {
    $signature = Get-AuthenticodeSignature -LiteralPath $file
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Anthropic, PBC') {
        throw "Official component signature failed: $file"
    }
}
if ([Environment]::OSVersion.Version.Build -lt 18362) { throw 'Claude requires Windows 10 build 18362 or newer.' }
$process = Start-Process -FilePath $installer -ArgumentList @('-local-msix', ('"{0}"' -f $msix)) -Verb RunAs -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Claude Setup exited with code $($process.ExitCode)" }
Write-Host 'Claude Desktop installation completed.' -ForegroundColor Green
'@
Set-Content -LiteralPath (Join-Path $outDir 'Install-Claude.ps1') -Value $installPs1 -Encoding UTF8
Set-Content -LiteralPath (Join-Path $outDir 'Install-Claude.cmd') -Value "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0Install-Claude.ps1`"`r`nexit /b %errorlevel%" -Encoding ASCII
if ($IncludeRuntime) {
    $codeExe = Join-Path $codeDir.FullName 'claude.exe'
    $vmBundle = Join-Path $RuntimeRoot 'vm_bundles\claudevm.bundle'
    $payload = Join-Path $outDir 'payload'
    New-Item -ItemType Directory -Force (Join-Path $payload "claude-code\$($codeDir.Name)") | Out-Null
    Copy-Item -LiteralPath $codeExe -Destination (Join-Path $payload "claude-code\$($codeDir.Name)\claude.exe")
    Copy-VMResources $vmBundle $outDir
    @("Claude Code version: $($codeDir.Name)", 'Cowork: local VM snapshot, not an independently verified latest release.', 'Only allowlisted files are included; no session or machine markers.') |
        Set-Content (Join-Path $outDir 'RUNTIME-MANIFEST.txt') -Encoding ASCII
    Copy-Item (Join-Path $PSScriptRoot 'install\Install-Claude-Full.ps1') (Join-Path $outDir 'Install-Claude-Full.ps1') -Force
    Copy-Item (Join-Path $PSScriptRoot 'install\Install-Cowork-VM.ps1') $outDir
    Set-Content -LiteralPath (Join-Path $outDir 'Install-Claude.cmd') -Value "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0Install-Claude-Full.ps1`"`r`nexit /b %errorlevel%" -Encoding ASCII
}
@("Claude Desktop Offline Package (unofficial wrapper)", "Version: $version", "Architecture: x64", "Runtime included: $IncludeRuntime", "", "Run Install-Claude.cmd as the intended Windows user; Setup requests elevation.", "Verify SHA256SUMS.txt before distribution.", 'The EXE includes Desktop and optional Code, never the Cowork VM payload.') |
    Set-Content -LiteralPath (Join-Path $outDir 'README.txt') -Encoding ASCII
if (-not $NoExe) {
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (-not (Test-Path $csc)) { throw "C# compiler not found: $csc" }
    $exe = Join-Path $OutputRoot "Claude-Desktop-$version.exe"
    $metadata = Join-Path $outDir 'AssemblyVersion.cs'
    "[assembly: System.Reflection.AssemblyVersion(`"$version`")]`r`n[assembly: System.Reflection.AssemblyFileVersion(`"$version`")]" |
        Set-Content -LiteralPath $metadata -Encoding ASCII
    $codeResources = @()
    if ($IncludeCode) {
        $codeExe = Join-Path $codeDir.FullName 'claude.exe'
        $codeResources = @("/resource:$codeExe,ClaudeCodeBinary")
        "Claude Code included in EXE: $($codeDir.Name)" | Add-Content (Join-Path $outDir 'README.txt')
    }
    if (-not $IconPath) {
        $IconPath = Join-Path $outDir 'Claude.ico'
        Export-ClaudeIcon $msixOut $IconPath
    }
    if (-not (Test-Path -LiteralPath $iconPath)) { throw "Installer icon not found: $iconPath" }
    & $csc /nologo /target:winexe /platform:x64 /optimize+ /reference:System.dll /reference:System.Windows.Forms.dll "/win32icon:$iconPath" "/resource:$setupOut,ClaudeSetup" "/resource:$msixOut,ClaudeMsix" @codeResources "/out:$exe" (Join-Path $PSScriptRoot '..\src\OfflineLauncher.cs') $metadata
    if ($LASTEXITCODE -ne 0) { throw 'Single-file EXE compilation failed.' }
    Remove-Item -LiteralPath $metadata
    ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash + '  ' + (Split-Path $exe -Leaf)) |
        Set-Content -LiteralPath "$exe.sha256" -Encoding ASCII
    Write-Host "Created: $exe" -ForegroundColor Green
}
$buildInfo = [ordered]@{
    DesktopVersion = $version
    MsixSource = $resolved
    Architecture = 'x64'
    CodeVersion = $(if ($codeDir) { $codeDir.Name } else { $null })
    CoworkIncluded = [bool]$IncludeRuntime
    BuiltAtUtc = [DateTime]::UtcNow.ToString('o')
}
$buildInfo | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $outDir 'BUILD-INFO.json') -Encoding ASCII
Write-PackageChecksums $outDir
Write-Host "Created: $outDir" -ForegroundColor Green
