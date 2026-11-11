[CmdletBinding()]
param(
    [switch]$VerifyOnly,
    [string]$PackageDirectory
)
$ErrorActionPreference = 'Stop'
# Resolve the default after Windows PowerShell 5.1 has bound script parameters.
if (-not $PSBoundParameters.ContainsKey('PackageDirectory')) { $PackageDirectory = $PSScriptRoot }
function Assert-PlainPath([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Reparse points are not supported: $cursor"
        }
        $cursor = Split-Path $cursor -Parent
    }
}
$PackageDirectory = [IO.Path]::GetFullPath($PackageDirectory)
Assert-PlainPath $PackageDirectory
$allowed = @('initrd', 'initrd.zst', 'rootfs.vhdx', 'rootfs.vhdx.zst', 'smol-bin.vhdx', 'vmlinuz', 'vmlinuz.zst')
$payload = Join-Path $PackageDirectory 'payload\claudevm.bundle'
Assert-PlainPath $payload
$manifest = Get-Content -LiteralPath (Join-Path $PackageDirectory 'VM-MANIFEST.json') -Raw | ConvertFrom-Json
if ($manifest.Count -ne $allowed.Count) { throw 'Unexpected manifest file count.' }
$actualFiles = @(Get-ChildItem -LiteralPath $payload -Force)
if ($actualFiles.Count -ne $allowed.Count -or ($actualFiles | Where-Object { $_.PSIsContainer -or $_.Name -cnotin $allowed })) {
    throw 'Unexpected VM payload files or directories.'
}
$seen = @{}
foreach ($item in $manifest) {
    if ($item.Name -cnotin $allowed -or $seen.ContainsKey($item.Name)) { throw 'Unexpected or duplicate payload name.' }
    $seen[$item.Name] = $true
    $file = Join-Path $payload $item.Name
    Assert-PlainPath $file
    if ($item.Length -le 0 -or $item.SHA256 -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid VM manifest entry.' }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing payload: $file" }
    if ((Get-Item -LiteralPath $file).Length -ne $item.Length -or
        (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $item.SHA256) {
        throw "Payload checksum failed: $($item.Name)"
    }
}
# Origin markers are generated from explicit, hash-matched official metadata, never copied from user state.
$origin = $null
$originPath = Join-Path $PackageDirectory 'VM-ORIGIN.json'
if (Test-Path -LiteralPath $originPath) {
    Assert-PlainPath $originPath
    $origin = Get-Content -LiteralPath $originPath -Raw | ConvertFrom-Json
    if ($origin.sha -notmatch '^[a-f0-9]{40}$' -or
        $origin.baseUrl -cne ('https://downloads.claude.ai/vms/linux/x64/' + $origin.sha) -or
        @($origin.files).Count -ne 3) { throw 'Invalid official VM origin metadata.' }
    $originSeen = @{}
    foreach ($resource in $origin.files) {
        if ($resource.name -cnotin @('rootfs.vhdx', 'vmlinuz', 'initrd') -or $originSeen.ContainsKey($resource.name)) {
            throw 'Unexpected or duplicate official VM origin resource.'
        }
        $originSeen[$resource.name] = $true
        $raw = @($manifest | Where-Object { $_.Name -ceq $resource.name })
        $compressed = @($manifest | Where-Object { $_.Name -ceq ($resource.name + '.zst') })
        if ($resource.rawChecksum -notmatch '^[a-fA-F0-9]{64}$' -or $resource.checksum -notmatch '^[a-fA-F0-9]{64}$' -or
            $raw.Count -ne 1 -or $compressed.Count -ne 1 -or
            $raw[0].SHA256 -ne $resource.rawChecksum -or $raw[0].Length -ne $resource.rawSize -or
            $compressed[0].SHA256 -ne $resource.checksum -or $compressed[0].Length -ne $resource.size) {
            throw 'Official VM origin hashes do not match the verified payload.'
        }
    }
}
$linuxCode = $null
$codePayload = Join-Path $PackageDirectory 'payload\claude-code-vm'
if (Test-Path -LiteralPath $codePayload) {
    Assert-PlainPath $codePayload
    $codeFiles = @(Get-ChildItem -LiteralPath $codePayload -Force)
    if ($codeFiles.Count -ne 2 -or ($codeFiles | Where-Object { $_.PSIsContainer -or $_.Name -cnotin @('claude', 'LINUX-CODE.json') })) { throw 'Unexpected Linux Code files.' }
    foreach ($file in $codeFiles) { Assert-PlainPath $file.FullName }
    $linuxCode = Get-Content -LiteralPath (Join-Path $codePayload 'LINUX-CODE.json') -Raw | ConvertFrom-Json
    if ($linuxCode.Version -notmatch '^\d+\.\d+\.\d+$' -or $linuxCode.Platform -cne 'linux-x64' -or
        $linuxCode.SHA256 -notmatch '^[a-f0-9]{64}$' -or $linuxCode.ArchiveSHA256 -notmatch '^[a-f0-9]{64}$' -or $linuxCode.Length -le 0) { throw 'Invalid Linux Code metadata.' }
    $codeBinary = Join-Path $codePayload 'claude'
    if ((Get-Item -LiteralPath $codeBinary).Length -ne $linuxCode.Length -or (Get-FileHash -LiteralPath $codeBinary).Hash -ne $linuxCode.SHA256) { throw 'Linux Code checksum failed.' }
}
Write-Host 'Payload checksums verified.' -ForegroundColor Green
if ($VerifyOnly) { return }
if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { throw 'Windows x64 is required.' }
$mutex = New-Object Threading.Mutex($false, 'Local\ClaudeChinesePack-CoworkInstall')
$locked = $false
try {
try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
if (-not $locked) { throw 'Another Cowork patch installation is running.' }
if (-not (Get-AppxPackage -Name Claude)) { throw 'Install Claude Desktop for this Windows user first.' }
if (Get-Process -Name Claude, 'claude-desktop', 'cowork' -ErrorAction SilentlyContinue) {
    throw 'Exit Claude Desktop and Cowork completely, then run this patch again.'
}
if ($linuxCode) {
    $codeParent = Join-Path $env:LOCALAPPDATA 'Claude-3p\claude-code-vm'
    $codeTarget = Join-Path $codeParent $linuxCode.Version
    Assert-PlainPath $codeTarget
    if (Test-Path -LiteralPath $codeTarget) {
        Get-ChildItem -LiteralPath $codeTarget -Recurse -Force | ForEach-Object { Assert-PlainPath $_.FullName }
    }
}
$parent = Join-Path $env:LOCALAPPDATA 'Claude-3p\vm_bundles'
$target = Join-Path $parent 'claudevm.bundle'
Assert-PlainPath $target
if (Test-Path -LiteralPath (Join-Path $target 'sessiondata.vhdx')) {
    throw 'Existing sessiondata.vhdx found. This patch will not replace a VM containing user sessions.'
}
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$drive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($parent).Substring(0,1))
$required = ($manifest | Measure-Object Length -Sum).Sum + 512MB
if ($linuxCode) { $required += $linuxCode.Length }
if ($drive.Free -lt $required) { throw 'Insufficient disk space for staged installation.' }
$suffix = [guid]::NewGuid().ToString('N')
$stage = Join-Path $parent "claudevm.staging-$suffix"
$backup = Join-Path $parent "claudevm.backup-$suffix"
New-Item -ItemType Directory -Path $stage | Out-Null
foreach ($item in $manifest) {
    $destination = Join-Path $stage $item.Name
    Copy-Item -LiteralPath (Join-Path $payload $item.Name) -Destination $destination
    if ((Get-FileHash -LiteralPath $destination).Hash -ne $item.SHA256) { throw "Staged copy failed: $($item.Name)" }
}
if ($origin) {
    foreach ($resource in $origin.files) {
        [IO.File]::WriteAllText((Join-Path $stage ('.' + $resource.name + '.origin')), [string]$origin.sha, [Text.Encoding]::ASCII)
    }
}
# Recheck just before the directory swap in case Claude was opened during copying.
if (Get-Process -Name Claude, 'claude-desktop', 'cowork' -ErrorAction SilentlyContinue) {
    throw "Claude is running. Installation stopped; staged files remain at $stage"
}
if (Test-Path -LiteralPath (Join-Path $target 'sessiondata.vhdx')) { throw 'A user session appeared; installation stopped.' }
Assert-PlainPath $target
$hadTarget = Test-Path -LiteralPath $target
if ($hadTarget) { Rename-Item -LiteralPath $target -NewName (Split-Path $backup -Leaf) }
try {
    Rename-Item -LiteralPath $stage -NewName 'claudevm.bundle'
} catch {
    if ($hadTarget) { Rename-Item -LiteralPath $backup -NewName 'claudevm.bundle' }
    throw
}
if ($linuxCode) {
    New-Item -ItemType Directory -Path $codeParent -Force | Out-Null
    $codeStage = Join-Path $codeParent ('code-stage-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $codeStage | Out-Null
    Copy-Item -LiteralPath $codeBinary -Destination (Join-Path $codeStage 'claude')
    if ((Get-FileHash -LiteralPath (Join-Path $codeStage 'claude')).Hash -ne $linuxCode.SHA256) { throw 'Staged Linux Code checksum failed.' }
    [IO.File]::WriteAllText((Join-Path $codeStage '.payload'), (@{sha256=$linuxCode.SHA256; size=$linuxCode.Length} | ConvertTo-Json), [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $codeStage '.verified'), $linuxCode.ArchiveSHA256, [Text.Encoding]::ASCII)
    if (Get-Process -Name Claude, 'claude-desktop', 'cowork' -ErrorAction SilentlyContinue) { throw 'Claude started during installation; Linux Code staging retained.' }
    Assert-PlainPath $codeTarget
    $codeBackup = $null
    if (Test-Path -LiteralPath $codeTarget) {
        $codeBackup = $linuxCode.Version + '.backup-' + [guid]::NewGuid().ToString('N')
        Rename-Item -LiteralPath $codeTarget -NewName $codeBackup
    }
    try { Rename-Item -LiteralPath $codeStage -NewName $linuxCode.Version } catch {
        if ($codeBackup) { Rename-Item -LiteralPath (Join-Path $codeParent $codeBackup) -NewName $linuxCode.Version }
        throw
    }
    Write-Host "Linux Code installed: $codeTarget"
    if ($codeBackup) { Write-Host "Previous Linux Code retained: $codeBackup" }
}
Write-Host "Cowork VM installed: $target" -ForegroundColor Green
if ($hadTarget) { Write-Host "Previous VM retained at: $backup" }
Write-Host 'Open Claude Desktop to test Cowork. No Windows features or account settings were changed.'
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
