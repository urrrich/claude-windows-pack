[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    # Obtain this checksum from the manifest embedded in the verified Desktop MSIX.
    [Parameter(Mandatory=$true)][ValidatePattern('^[a-f0-9]{64}$')][string]$ArchiveSHA256,
    [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'lib\Packaging.Common.ps1')
$Output = [IO.Path]::GetFullPath($Output)
Assert-PlainPath $Output
if (Test-Path -LiteralPath $Output) { throw 'Output already exists; use a new directory.' }
$node = (Get-Command node -ErrorAction Stop).Source
& $node -e 'if(typeof require("zlib").createZstdDecompress!=="function") process.exit(1)'
if ($LASTEXITCODE -ne 0) { throw 'Node.js with Zstandard decompression is required.' }
New-Item -ItemType Directory -Path $Output | Out-Null
$base = "https://downloads.claude.ai/claude-code-releases/$Version"
$upstream = Invoke-RestMethod "$base/manifest.json"
$expected = $upstream.platforms.'linux-x64'
if ($expected.checksum -notmatch '^[a-f0-9]{64}$' -or $expected.size -le 0) { throw 'Invalid official Linux Code manifest.' }
$archive = Join-Path $Output 'claude.zst'
$binary = Join-Path $Output 'claude'
Invoke-WebRequest -UseBasicParsing -Uri "$base/linux-x64/claude.zst" -OutFile $archive
if ((Get-FileHash -LiteralPath $archive).Hash -ne $ArchiveSHA256) { throw 'Compressed Linux Code checksum mismatch.' }
& $node -e 'const fs=require("fs"),z=require("zlib");require("stream/promises").pipeline(fs.createReadStream(process.argv[1]),z.createZstdDecompress(),fs.createWriteStream(process.argv[2],{flags:"wx"})).catch(e=>{console.error(e);process.exit(1)})' $archive $binary
if ($LASTEXITCODE -ne 0) { throw 'Linux Code decompression failed.' }
if ((Get-FileHash -LiteralPath $binary).Hash -ne $expected.checksum -or (Get-Item -LiteralPath $binary).Length -ne $expected.size) { throw 'Official Linux Code payload checksum/size mismatch.' }
@{Version=$Version; Platform='linux-x64'; Length=$expected.size; SHA256=$expected.checksum; ArchiveSHA256=$ArchiveSHA256; Source="$base/linux-x64/claude.zst"} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Output 'LINUX-CODE.json') -Encoding ASCII
$upstream | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $Output 'upstream-manifest.json') -Encoding ASCII
Write-Host "Verified Linux Code: $binary"