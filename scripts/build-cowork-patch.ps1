[CmdletBinding()]
param(
    [string]$Source = (Join-Path $env:LOCALAPPDATA 'Claude-3p\vm_bundles\claudevm.bundle'),
    [string]$Output = (Join-Path $PSScriptRoot ("..\releases\Cowork-VM-Patch-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-x64')),
    [switch]$CreateInstaller,
    [string]$IconPath,
    [string]$LinuxCodeDirectory,
    [string]$OfficialVmManifest
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Packaging.Common.ps1')
$Output = [IO.Path]::GetFullPath($Output)
Assert-PlainPath $Output
if (Test-Path -LiteralPath $Output) { throw "Output already exists: $Output" }
Copy-VMResources $Source $Output
if ($LinuxCodeDirectory) {
    Assert-PlainPath $LinuxCodeDirectory
    $codeOut = Join-Path $Output 'payload\claude-code-vm'
    New-Item -ItemType Directory -Path $codeOut | Out-Null
    foreach ($file in @('claude', 'LINUX-CODE.json')) {
        Assert-PlainPath (Join-Path $LinuxCodeDirectory $file)
        Copy-Item -LiteralPath (Join-Path $LinuxCodeDirectory $file) -Destination (Join-Path $codeOut $file)
    }
}
foreach ($name in @('Install-Cowork-VM.cmd', 'Install-Cowork-VM.ps1')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "install\$name") -Destination $Output
}
if ($OfficialVmManifest) {
    Assert-PlainPath $OfficialVmManifest
    Copy-Item -LiteralPath $OfficialVmManifest -Destination (Join-Path $Output 'VM-ORIGIN.json')
    & (Join-Path $PSScriptRoot 'install\Install-Cowork-VM.ps1') -PackageDirectory $Output -VerifyOnly
}
@(
    'Cowork VM offline patch - Windows x64'
    "Local runtime snapshot built at $([DateTime]::UtcNow.ToString('o')). Not independently verified as the latest VM release."
    'Keep the entire directory together. Double-click Install-Cowork-VM.cmd.'
    'Run as the Windows user who uses Claude Desktop; administrator elevation is not required.'
    'Install Claude Desktop first and fully exit Claude/Cowork before applying.'
    'Existing VM is retained as a backup. Existing sessiondata.vhdx prevents installation.'
    'Only seven allowlisted VM resources are included. No sessions, credentials or copied origin/repair markers.'
    'With a verified official VM manifest, the installer generates version-origin markers after checking all declared hashes.'
    'This patch does not enable Windows virtualization features or configure account access.'
    'Verification only: powershell -NoProfile -ExecutionPolicy Bypass -File Install-Cowork-VM.ps1 -VerifyOnly'
) | Set-Content -LiteralPath (Join-Path $Output 'README.txt') -Encoding ASCII
& (Join-Path $PSScriptRoot 'install\Install-Cowork-VM.ps1') -PackageDirectory $Output -VerifyOnly
Write-PackageChecksums $Output
Write-Host "Created: $Output" -ForegroundColor Green
if ($CreateInstaller) {
    & (Join-Path $PSScriptRoot 'build-cowork-installer.ps1') -PatchDirectory $Output -IconPath $IconPath
}
