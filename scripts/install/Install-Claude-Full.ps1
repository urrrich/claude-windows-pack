[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$codeDirectories = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'payload\claude-code') -Directory)
if ($codeDirectories.Count -ne 1 -or $codeDirectories[0].Name -notmatch '^\d+\.\d+\.\d+$') {
    throw 'Exactly one versioned Claude Code payload is required.'
}
$codeSource = $codeDirectories[0]
$code = Join-Path $codeSource.FullName 'claude.exe'
$signature = Get-AuthenticodeSignature -LiteralPath $code
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Anthropic, PBC') {
    throw 'Claude Code signature verification failed.'
}
if (([version](Get-Item -LiteralPath $code).VersionInfo.ProductVersion).ToString(3) -ne $codeSource.Name) {
    throw 'Claude Code version mismatch.'
}
& (Join-Path $PSScriptRoot 'Install-Cowork-VM.ps1') -VerifyOnly
& (Join-Path $PSScriptRoot 'Install-Claude.ps1')
$destination = Join-Path $env:LOCALAPPDATA "Claude-3p\claude-code\$($codeSource.Name)"
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -LiteralPath $code -Destination (Join-Path $destination 'claude.exe') -Force
# VM installation remains guarded and backed up by the standalone patch installer.
& (Join-Path $PSScriptRoot 'Install-Cowork-VM.ps1')
Write-Host 'Claude Desktop, Code and Cowork VM installation completed.' -ForegroundColor Green
