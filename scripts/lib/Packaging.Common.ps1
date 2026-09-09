# Runtime collection is allowlisted, never a recursive copy of user data.
$VmFiles = @('initrd', 'initrd.zst', 'rootfs.vhdx', 'rootfs.vhdx.zst', 'smol-bin.vhdx', 'vmlinuz', 'vmlinuz.zst')

function Assert-PlainPath([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse points are not supported: $cursor"
            }
        }
        $cursor = Split-Path $cursor -Parent
    }
}

function Assert-AnthropicSignature([string]$Path) {
    Assert-PlainPath $Path
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O="?Anthropic, PBC"?(,|$)') {
        throw "Anthropic signature verification failed: $Path ($($signature.Status))"
    }
}

function Get-CodeRuntime([string]$Root) {
    $directory = Get-ChildItem -LiteralPath (Join-Path $Root 'claude-code') -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $directory) { throw "No Claude Code runtime found under $Root" }
    $binary = Join-Path $directory.FullName 'claude.exe'
    Assert-AnthropicSignature $binary
    $version = [version](Get-Item -LiteralPath $binary).VersionInfo.ProductVersion
    if ($version.ToString(3) -ne $directory.Name) { throw 'Code file version does not match its directory.' }
    return $directory
}

function Write-PackageChecksums([string]$Directory) {
    $root = [IO.Path]::GetFullPath($Directory).TrimEnd('\')
    $lines = @(Get-ChildItem -LiteralPath $root -File -Recurse |
        Where-Object { $_.FullName -ne (Join-Path $root 'SHA256SUMS.txt') } |
        Sort-Object FullName | ForEach-Object {
            (Get-FileHash -LiteralPath $_.FullName).Hash + '  ' + $_.FullName.Substring($root.Length + 1)
        })
    $lines | Set-Content -LiteralPath (Join-Path $root 'SHA256SUMS.txt') -Encoding ASCII
}

function Copy-VMResources([string]$Source, [string]$PackageDirectory) {
    Assert-PlainPath $Source
    foreach ($name in $VmFiles) {
        $file = Get-Item -LiteralPath (Join-Path $Source $name)
        Assert-PlainPath $file.FullName
        if ($file.Length -le 0) { throw "Empty VM resource: $name" }
    }
    $payload = Join-Path $PackageDirectory 'payload\claudevm.bundle'
    if (Test-Path -LiteralPath $payload) { throw "VM payload already exists: $payload" }
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    $manifest = foreach ($name in $VmFiles) {
        Write-Host "Copying and verifying $name..."
        $sourceFile = Join-Path $Source $name
        $before = (Get-FileHash -LiteralPath $sourceFile).Hash
        $destination = Join-Path $payload $name
        Copy-Item -LiteralPath $sourceFile -Destination $destination
        $after = (Get-FileHash -LiteralPath $destination).Hash
        if ($before -ne $after) { throw "VM source changed or copy failed: $name" }
        [pscustomobject]@{Name=$name; Length=(Get-Item -LiteralPath $destination).Length; SHA256=$after}
    }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PackageDirectory 'VM-MANIFEST.json') -Encoding ASCII
}

function Get-MsixIdentity([string]$Path) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $entry = $archive.GetEntry('AppxManifest.xml')
        if (-not $entry) { throw 'MSIX manifest missing.' }
        $stream = $entry.Open()
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $reader = [System.Xml.XmlReader]::Create($stream, $settings)
        try {
            $document = New-Object System.Xml.XmlDocument
            $document.XmlResolver = $null
            $document.Load($reader)
            return $document.DocumentElement.SelectSingleNode("*[local-name()='Identity']")
        } finally { $reader.Dispose(); $stream.Dispose() }
    } finally { $archive.Dispose() }
}

function Export-ClaudeIcon([string]$Msix, [string]$Destination) {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Msix)
    $images = @()
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    try {
        $entry = $archive.GetEntry('assets/Square150x150Logo.png')
        if (-not $entry) { throw 'Official icon asset missing; supply -IconPath explicitly.' }
        $stream = $entry.Open()
        $image = [Drawing.Image]::FromStream($stream)
        try {
            foreach ($size in $sizes) {
                $bitmap = New-Object Drawing.Bitmap($size, $size)
                $graphics = [Drawing.Graphics]::FromImage($bitmap)
                $memory = New-Object IO.MemoryStream
                try {
                    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                    $graphics.DrawImage($image, 0, 0, $size, $size)
                    $bitmap.Save($memory, [Drawing.Imaging.ImageFormat]::Png)
                    $images += ,$memory.ToArray()
                } finally { $memory.Dispose(); $graphics.Dispose(); $bitmap.Dispose() }
            }
        } finally { $image.Dispose(); $stream.Dispose() }
    } finally { $archive.Dispose() }
    $writer = New-Object IO.BinaryWriter([IO.File]::Create($Destination))
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {
            $dimension = if ($sizes[$i] -eq 256) { 0 } else { $sizes[$i] }
            $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
            $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]32)
            $writer.Write([uint32]$images[$i].Length); $writer.Write([uint32]$offset)
            $offset += $images[$i].Length
        }
        foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }
    } finally { $writer.Dispose() }
}
