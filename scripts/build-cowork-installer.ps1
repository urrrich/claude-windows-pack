[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$PatchDirectory,
    [string]$Output,
    [string]$IconPath,
    [ValidateRange(1, 2000000000)][long]$MaxArchivePartBytes = 1900000000
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\Packaging.Common.ps1')
$PatchDirectory = (Resolve-Path -LiteralPath $PatchDirectory).Path
Assert-PlainPath $PatchDirectory
Get-ChildItem -LiteralPath $PatchDirectory -Recurse -Force | ForEach-Object { Assert-PlainPath $_.FullName }
$name = Split-Path $PatchDirectory -Leaf
if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$') { throw 'Patch directory name must contain only ASCII letters, digits, dot, underscore or hyphen.' }
if (-not $Output) { $Output = "$PatchDirectory-Installer" }
$Output = [IO.Path]::GetFullPath($Output)
Assert-PlainPath $Output
if ($Output.StartsWith($PatchDirectory.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase) -or $Output -eq $PatchDirectory) {
    throw 'Installer output must not be inside the patch directory.'
}
if (Test-Path -LiteralPath $Output) { throw "Output already exists: $Output" }
& (Join-Path $PSScriptRoot 'install\Install-Cowork-VM.ps1') -PackageDirectory $PatchDirectory -VerifyOnly
$allowed = @('Install-Cowork-VM.ps1', 'Install-Cowork-VM.cmd', 'README.txt', 'SHA256SUMS.txt', 'VM-MANIFEST.json', 'VM-ORIGIN.json')
$allowed += @('payload\claude-code-vm\claude', 'payload\claude-code-vm\LINUX-CODE.json')
$allowed += @($VmFiles | ForEach-Object { "payload\claudevm.bundle\$_" })
foreach ($file in (Get-ChildItem -LiteralPath $PatchDirectory -Recurse -File -Force)) {
    $relative = $file.FullName.Substring($PatchDirectory.TrimEnd('\').Length + 1)
    if ($relative -cnotin $allowed) { throw "Unexpected archive input: $relative" }
}
foreach ($script in @('Install-Cowork-VM.ps1', 'Install-Cowork-VM.cmd')) {
    if ((Get-FileHash -LiteralPath (Join-Path $PatchDirectory $script)).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "install\$script")).Hash) {
        throw "Patch script differs from this checkout: $script. Rebuild the patch directory first."
    }
}
New-Item -ItemType Directory -Path $Output | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $Output "$name.zip"
Write-Host 'Compressing Cowork payload...'
[IO.Compression.ZipFile]::CreateFromDirectory($PatchDirectory, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
$archiveSize = (Get-Item -LiteralPath $zip).Length
$partCount = 0
if ($archiveSize -gt $MaxArchivePartBytes) {
    $partCount = [int][Math]::Ceiling($archiveSize / [double]$MaxArchivePartBytes)
    if ($partCount -gt 999) { throw 'Too many archive parts.' }
    $inputStream = [IO.File]::OpenRead($zip)
    try {
        $buffer = New-Object byte[] (1MB)
        for ($part = 1; $part -le $partCount; $part++) {
            $partPath = $zip + ('.{0:D3}' -f $part)
            $outputStream = [IO.File]::Open($partPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
            try {
                $remaining = [Math]::Min($MaxArchivePartBytes, $archiveSize - $inputStream.Position)
                while ($remaining -gt 0) {
                    $read = $inputStream.Read($buffer, 0, [int][Math]::Min($buffer.Length, $remaining))
                    if ($read -le 0) { throw 'Unexpected end of ZIP while splitting.' }
                    $outputStream.Write($buffer, 0, $read)
                    $remaining -= $read
                }
            } finally { $outputStream.Dispose() }
        }
    } finally { $inputStream.Dispose() }
}
$partsPath = Join-Path $Output 'archive-parts.txt'
@([string]$partCount, [string]$archiveSize) | Set-Content -LiteralPath $partsPath -Encoding ASCII
$hashPath = Join-Path $Output 'archive.sha256'
$namePath = Join-Path $Output 'archive-name.txt'
(Get-FileHash -LiteralPath $zip).Hash | Set-Content -LiteralPath $hashPath -Encoding ASCII
$name | Set-Content -LiteralPath $namePath -Encoding ASCII
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$iconArgument = @()
if ($IconPath) {
    if (-not (Test-Path -LiteralPath $IconPath -PathType Leaf)) { throw 'Icon file not found.' }
    $iconArgument = @("/win32icon:$([IO.Path]::GetFullPath($IconPath))")
}
$exe = Join-Path $Output 'Install-Cowork-VM.exe'
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll @iconArgument "/resource:$partsPath,ArchiveParts" "/resource:$hashPath,ArchiveHash" "/resource:$namePath,ArchiveName" "/out:$exe" (Join-Path $PSScriptRoot '..\src\CoworkPatchLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw 'Cowork installer compilation failed.' }
@(
    'Unofficial Cowork VM patch installer'
    'Keep Install-Cowork-VM.exe and either the ZIP or ALL .zip.001, .zip.002, ... parts in the same directory.'
    'The installer combines split parts automatically and verifies the complete ZIP SHA-256.'
    'The full ZIP is retained locally; upload only the parts when the ZIP exceeds the hosting size limit.'
    'Double-click the EXE and click Install. Do not extract the ZIP manually.'
    'Run as the Windows user who uses Claude Desktop. Exit Claude before installation.'
    'The wrapper EXE is unsigned unless you sign it separately.'
) | Set-Content -LiteralPath (Join-Path $Output 'README.txt') -Encoding ASCII
Write-PackageChecksums $Output
Write-Host "Created: $Output"
