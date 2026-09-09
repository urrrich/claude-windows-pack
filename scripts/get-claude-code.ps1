[CmdletBinding()]
param(
    [ValidatePattern('^(latest|stable|\d+\.\d+\.\d+)$')][string]$Version = 'latest',
    [string]$RuntimeRoot = (Join-Path $PSScriptRoot '..\build-runtime')
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'lib\Packaging.Common.ps1')
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$base = 'https://downloads.claude.ai/claude-code-releases'
if ($Version -in @('latest', 'stable')) { $Version = ([string](Invoke-RestMethod "$base/$Version")).Trim() }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Unexpected Code version response.' }
$manifest = Invoke-RestMethod "$base/$Version/manifest.json"
$platform = $manifest.platforms.'win32-x64'
if ($platform.checksum -notmatch '^[a-fA-F0-9]{64}$' -or $platform.size -le 0) { throw 'Invalid official manifest.' }
$directory = [IO.Path]::GetFullPath((Join-Path $RuntimeRoot "claude-code\$Version"))
Assert-PlainPath $directory
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$binary = Join-Path $directory 'claude.exe'
$partial = Join-Path $directory ("claude-" + [guid]::NewGuid().ToString('N') + '.partial')
Write-Host "Downloading official Claude Code $Version (win32-x64)..."
Invoke-WebRequest -UseBasicParsing -Uri "$base/$Version/win32-x64/claude.exe" -OutFile $partial
if ((Get-Item -LiteralPath $partial).Length -ne $platform.size -or
    (Get-FileHash -LiteralPath $partial).Hash -ne $platform.checksum) { throw 'Official Code checksum/size mismatch.' }
Assert-AnthropicSignature $partial
$fileVersion = [version](Get-Item -LiteralPath $partial).VersionInfo.ProductVersion
if ($fileVersion.ToString(3) -ne $Version) { throw 'Code binary version mismatch.' }
Move-Item -LiteralPath $partial -Destination $binary -Force
Write-Host "Verified: $binary"
