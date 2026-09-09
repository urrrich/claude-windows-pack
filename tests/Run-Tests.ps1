[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts\lib\Packaging.Common.ps1')
$scripts = Join-Path $root 'scripts'
$vmInstaller = Join-Path $scripts 'install\Install-Cowork-VM.ps1'
$testRoot = Join-Path $root ('releases\tests with spaces-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Must-Fail([scriptblock]$Action, [string]$Pattern) {
    $failed = $false
    try { & $Action } catch {
        $failed = $true
        if ($_.Exception.Message -notmatch $Pattern) { throw "Unexpected error: $($_.Exception.Message)" }
    }
    Assert $failed "Expected failure matching: $Pattern"
}

$sourceFiles = @(Get-ChildItem -LiteralPath $scripts, $PSScriptRoot -File -Filter '*.ps1' -Recurse)
foreach ($file in $sourceFiles) {
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors) | Out-Null
    Assert (-not $errors) "PowerShell syntax error: $($file.Name)"
}
$tracked = @(& git -C $root ls-files)
Assert ($LASTEXITCODE -eq 0) 'Git file inventory failed.'
foreach ($file in $tracked) {
    Assert ($file -notmatch '(?i)(^releases/|^build-runtime/|^verification|sessiondata|\.env$|\.(exe|msix|vhdx|zst|zip|ico|pem|key|pfx)$)') "Forbidden tracked file: $file"
    Assert ((Get-Item -LiteralPath (Join-Path $root $file)).Length -lt 1MB) "Unexpectedly large source file: $file"
}
Write-Host 'Source syntax and tracked-file policy: PASS'

$source = Join-Path $testRoot 'source'
New-Item -ItemType Directory -Path $source | Out-Null
foreach ($name in $VmFiles) { [IO.File]::WriteAllText((Join-Path $source $name), "synthetic fixture $name") }
[IO.File]::WriteAllText((Join-Path $source 'sessiondata.vhdx'), 'DO NOT COPY')
[IO.File]::WriteAllText((Join-Path $source '.rootfs.vhdx.origin'), 'DO NOT COPY')
$patch = Join-Path $testRoot 'fixture-patch'
& (Join-Path $scripts 'build-cowork-patch.ps1') -Source $source -Output $patch
$payload = Join-Path $patch 'payload\claudevm.bundle'
Assert (@(Get-ChildItem -LiteralPath $payload -Force).Count -eq 7) 'VM allowlist was not enforced.'
& $vmInstaller -PackageDirectory $patch -VerifyOnly
$binary = Join-Path $payload 'initrd'
[IO.File]::WriteAllText($binary, 'tampered')
Must-Fail { & $vmInstaller -PackageDirectory $patch -VerifyOnly } 'checksum'
Copy-Item -LiteralPath (Join-Path $source 'initrd') -Destination $binary -Force
$manifestPath = Join-Path $patch 'VM-MANIFEST.json'
$originalManifest = [IO.File]::ReadAllText($manifestPath)
$manifest = $originalManifest | ConvertFrom-Json
$manifest[0].Name = '..\outside'
$manifest | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding ASCII
Must-Fail { & $vmInstaller -PackageDirectory $patch -VerifyOnly } 'Unexpected or duplicate'
[IO.File]::WriteAllText($manifestPath, $originalManifest)
Write-Host 'VM allowlist, checksum and traversal guards: PASS'

# Mock the OS probes and redirect LocalAppData into the fixture directory.
$savedLocal = $env:LOCALAPPDATA
function Get-AppxPackage { param($Name) [pscustomobject]@{Name='Claude'} }
function Get-Process { param($Name, $ErrorAction) return @() }
try {
    $env:LOCALAPPDATA = Join-Path $testRoot 'local'
    $target = Join-Path $env:LOCALAPPDATA 'Claude-3p\vm_bundles\claudevm.bundle'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $target 'old.txt'), 'preserve old VM')
    & $vmInstaller -PackageDirectory $patch
    Assert (Test-Path -LiteralPath (Join-Path $target 'rootfs.vhdx')) 'VM not installed in fixture target.'
    $backups = @(Get-ChildItem -LiteralPath (Split-Path $target -Parent) -Directory -Filter 'claudevm.backup-*')
    Assert ($backups.Count -eq 1) 'Old VM was not backed up.'
    Assert (Test-Path -LiteralPath (Join-Path $backups[0].FullName 'old.txt')) 'Backup contents lost.'
    [IO.File]::WriteAllText((Join-Path $target 'sessiondata.vhdx'), 'user session fixture')
    Must-Fail { & $vmInstaller -PackageDirectory $patch } 'sessiondata'
    Assert (Test-Path -LiteralPath (Join-Path $target 'sessiondata.vhdx')) 'Session file was removed.'
} finally {
    $env:LOCALAPPDATA = $savedLocal
    Remove-Item Function:\Get-AppxPackage, Function:\Get-Process
}
Write-Host 'Synthetic installation, backup and session protection: PASS'

& (Join-Path $scripts 'build-cowork-installer.ps1') -PatchDirectory $patch
$installerDir = "$patch-Installer"
$assembly = [Reflection.Assembly]::LoadFile((Join-Path $installerDir 'Install-Cowork-VM.exe'))
Add-Type -AssemblyName System.Windows.Forms
$form = [Activator]::CreateInstance($assembly.GetType('CoworkPatchLauncher'), $true)
try { Assert ($form.Controls.Count -eq 4) 'Cowork GUI failed to initialize.' } finally { $form.Dispose() }
$zip = [IO.Compression.ZipFile]::OpenRead((Join-Path $installerDir 'fixture-patch.zip'))
try {
    foreach ($entry in $zip.Entries) {
        if (-not $entry.Name) { continue }
        $relative = $entry.FullName.Substring('fixture-patch/'.Length)
        $stream = $entry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '')
            Assert ($hash -eq (Get-FileHash -LiteralPath (Join-Path $patch $relative)).Hash) 'ZIP round-trip mismatch.'
        } finally { $stream.Dispose(); $sha.Dispose() }
    }
} finally { $zip.Dispose() }
Write-Host 'Cowork EXE compilation, GUI and ZIP integrity: PASS'

$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$desktop = Join-Path $testRoot 'DesktopFixture.exe'
& $compiler /nologo /target:winexe /platform:x64 /reference:System.dll /reference:System.Windows.Forms.dll "/resource:$binary,ClaudeSetup" "/resource:$binary,ClaudeMsix" "/resource:$binary,ClaudeCodeBinary" "/out:$desktop" (Join-Path $root 'src\OfflineLauncher.cs')
Assert ($LASTEXITCODE -eq 0) 'Desktop C# compilation failed.'
$extracted = Join-Path $testRoot 'extracted with spaces'
$process = Start-Process -FilePath $desktop -ArgumentList @('--extract-only', ('"{0}"' -f $extracted)) -WindowStyle Hidden -Wait -PassThru
Assert ($process.ExitCode -eq 0) 'Desktop extract-only failed.'
foreach ($name in @('Claude Setup.exe', 'Claude-x64.msix', 'claude.exe')) {
    Assert ((Get-FileHash -LiteralPath (Join-Path $extracted $name)).Hash -eq (Get-FileHash -LiteralPath $binary).Hash) 'Embedded Desktop resource mismatch.'
}
Write-Host 'Desktop EXE compilation and extract-only round trip: PASS'
Write-Host "All tests passed. Fixtures retained under $testRoot"
