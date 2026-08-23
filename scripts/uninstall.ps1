[CmdletBinding()]
param(
    [string]$RimeUserDir = "",
    [switch]$DryRun,
    [switch]$Apply,
    [switch]$NoBackup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($DryRun -and $Apply) {
    throw "-DryRun and -Apply are mutually exclusive."
}

if ([string]::IsNullOrWhiteSpace($RimeUserDir)) {
    if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
        throw "APPDATA is unavailable. Pass -RimeUserDir with the Rime user directory."
    }
    $RimeUserDir = Join-Path $env:APPDATA "Rime"
}

function Normalize-FullPath {
    param([string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        return $full.TrimEnd([char[]]@('\', '/'))
    }
    return $full
}

function Get-ExistingItem {
    param([string]$Path)

    try {
        return Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        if ($_.CategoryInfo.Category -eq "ObjectNotFound") {
            return $null
        }
        throw
    }
}

$Target = Normalize-FullPath -Path $RimeUserDir
$ManifestName = ".rime-smart-simplified.install-manifest"
$ManifestPath = Join-Path $Target $ManifestName

function Get-Sha256 {
    param([string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-UniqueBackupDirectory {
    param([string]$BasePath)

    $suffix = 0
    while ($true) {
        $candidate = if ($suffix -eq 0) { $BasePath } else { "$BasePath.$suffix" }
        if (Test-Path -LiteralPath $candidate) {
            $suffix += 1
            continue
        }
        try {
            New-Item -ItemType Directory -Path $candidate -ErrorAction Stop | Out-Null
            return $candidate
        } catch [System.IO.IOException] {
            if (-not (Test-Path -LiteralPath $candidate)) {
                throw
            }
            $suffix += 1
        }
    }
}

function Assert-SafeRelativePath {
    param([string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains("`t") -or
        $RelativePath.Contains(":") -or
        $RelativePath.IndexOf([char]0) -ge 0) {
        throw "Invalid ownership manifest path: $RelativePath"
    }
    $parts = $RelativePath.Replace("\", "/").Split("/")
    if ($parts | Where-Object { $_ -eq "" -or $_ -eq "." -or $_ -eq ".." }) {
        throw "Invalid ownership manifest path: $RelativePath"
    }
}

function Assert-NoReparsePointBelowTarget {
    param([string]$DestinationPath)

    $targetFull = Normalize-FullPath -Path $Target
    $current = Normalize-FullPath -Path $DestinationPath
    while (-not [string]::Equals(
        $current,
        $targetFull,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        $item = Get-ExistingItem -Path $current
        if ($null -ne $item) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to inspect through a symlink or junction below the Rime target: $current"
            }
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            throw "Owned path is not contained by the Rime target: $DestinationPath"
        }
        $current = Normalize-FullPath -Path $parent
    }
}

$manifestItem = Get-ExistingItem -Path $ManifestPath
if ($null -eq $manifestItem) {
    Write-Error "No ownership manifest found at $ManifestPath. Run the current installer once before precise uninstall."
    exit 2
}

if (($manifestItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Refusing to read a symlinked install manifest: $ManifestPath"
}
if ($manifestItem.PSIsContainer) {
    throw "Refusing to read a non-regular install manifest: $ManifestPath"
}

$lines = [System.IO.File]::ReadAllLines($ManifestPath, [System.Text.Encoding]::UTF8)
if ($lines.Count -eq 0 -or $lines[0] -ne "# rime-smart-simplified install manifest v2") {
    throw "Unsupported or legacy ownership manifest; refusing deletion: $ManifestPath"
}

$Candidates = New-Object System.Collections.ArrayList
$Preserved = New-Object System.Collections.ArrayList
$Missing = New-Object System.Collections.ArrayList
$SeenRelativePaths = @()

foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) {
        continue
    }
    $fields = $line.Split("`t")
    if ($fields.Count -ne 5 -or $fields[0] -ne "file") {
        throw "Invalid ownership manifest entry: $line"
    }
    $relativePath = $fields[1]
    $installedSha = $fields[2].ToLowerInvariant()
    $sourceSha = $fields[3].ToLowerInvariant()
    $ownership = $fields[4]
    Assert-SafeRelativePath -RelativePath $relativePath
    if ($installedSha -notmatch '^[0-9a-f]{64}$' -or $sourceSha -notmatch '^[0-9a-f]{64}$') {
        throw "Invalid ownership digest for: $relativePath"
    }
    if ($ownership -notin @("managed", "asset-created")) {
        throw "Unsupported ownership class for $relativePath`: $ownership"
    }

    if ($SeenRelativePaths -contains $relativePath) {
        throw "Duplicate ownership manifest entry: $relativePath"
    }
    $SeenRelativePaths += $relativePath

    $path = Join-Path $Target $relativePath
    Assert-NoReparsePointBelowTarget -DestinationPath $path
    $pathItem = Get-ExistingItem -Path $path
    if ($null -eq $pathItem) {
        [void]$Missing.Add($relativePath)
        continue
    }
    if ($pathItem.PSIsContainer) {
        throw "Refusing to remove a non-regular owned path: $path"
    }
    $actualSha = Get-Sha256 -Path $path
    if ($actualSha -eq $installedSha) {
        [void]$Candidates.Add([PSCustomObject]@{
            RelativePath = $relativePath
            Path = $path
            Digest = $installedSha
        })
    } else {
        [void]$Preserved.Add("$relativePath (edited; digest differs)")
    }
}

if ($Preserved.Count -gt 0) {
    [void]$Preserved.Add("$ManifestName (retained because edited files remain)")
} else {
    [void]$Candidates.Add([PSCustomObject]@{
        RelativePath = $ManifestName
        Path = $ManifestPath
        Digest = Get-Sha256 -Path $ManifestPath
    })
}

Write-Output "Target: $Target"
Write-Output "Ownership manifest: $ManifestPath"
Write-Output "Deletion candidates (content unchanged since install):"
if ($Candidates.Count -eq 0) {
    Write-Output "  (none)"
} else {
    $Candidates | ForEach-Object { Write-Output "  REMOVE $($_.RelativePath)" }
}
if ($Preserved.Count -gt 0) {
    Write-Output "Preserved files (edited or private):"
    $Preserved | ForEach-Object { Write-Output "  KEEP   $_" }
}
if ($Missing.Count -gt 0) {
    Write-Output "Already absent:"
    $Missing | ForEach-Object { Write-Output "  ABSENT $_" }
}

if (-not $Apply) {
    Write-Output "Dry run only; re-run with -Apply to remove unchanged package files."
    exit 0
}

$BackupDir = $null
$Deleted = New-Object System.Collections.ArrayList
if (-not $NoBackup) {
    $BackupDir = New-UniqueBackupDirectory -BasePath "$Target.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    foreach ($candidate in $Candidates) {
        $candidateItem = Get-ExistingItem -Path $candidate.Path
        if ($null -ne $candidateItem -and -not $candidateItem.PSIsContainer) {
            $backupPath = Join-Path $BackupDir $candidate.RelativePath
            $backupParent = Split-Path -Parent $backupPath
            if (-not [string]::IsNullOrWhiteSpace($backupParent)) {
                New-Item -ItemType Directory -Force -Path $backupParent | Out-Null
            }
            Copy-Item -LiteralPath $candidate.Path -Destination $backupPath -Force
        }
    }
    Write-Output "Backup: $BackupDir"
} else {
    Write-Output "Backup: skipped by -NoBackup (failure cannot be restored automatically)."
}

try {
    foreach ($candidate in $Candidates) {
        $candidateItem = Get-ExistingItem -Path $candidate.Path
        if ($null -eq $candidateItem) {
            continue
        }
        Assert-NoReparsePointBelowTarget -DestinationPath $candidate.Path
        if ($candidate.RelativePath -eq $ManifestName -and $Preserved.Count -gt 0) {
            continue
        }
        if ($candidateItem.PSIsContainer) {
            throw "Refusing to remove a non-regular owned path: $($candidate.Path)"
        }
        if ((Get-Sha256 -Path $candidate.Path) -ne $candidate.Digest) {
            [void]$Preserved.Add("$($candidate.RelativePath) (changed during uninstall; preserved)")
            continue
        }
        Remove-Item -LiteralPath $candidate.Path -Force
        [void]$Deleted.Add($candidate.RelativePath)
    }
} catch {
    $failure = $_
    $recoveryErrors = New-Object System.Collections.ArrayList
    if ($null -ne $BackupDir) {
        foreach ($relativePath in $Deleted) {
            try {
                $backupPath = Join-Path $BackupDir $relativePath
                $destination = Join-Path $Target $relativePath
                $parent = Split-Path -Parent $destination
                if (-not [string]::IsNullOrWhiteSpace($parent)) {
                    New-Item -ItemType Directory -Force -Path $parent | Out-Null
                }
                Copy-Item -LiteralPath $backupPath -Destination $destination -Force
            } catch {
                [void]$recoveryErrors.Add("$relativePath`: $($_.Exception.Message)")
            }
        }
    }
    if ($recoveryErrors.Count -gt 0) {
        throw "Uninstall failed: $($failure.Exception.Message) Recovery INCOMPLETE: $($recoveryErrors -join '; '). Backup: $BackupDir"
    }
    if ($null -ne $BackupDir) {
        throw "Uninstall failed: $($failure.Exception.Message) Deleted files restored from: $BackupDir"
    }
    throw "Uninstall failed after -NoBackup: $($failure.Exception.Message)"
}

Write-Output "Uninstalled $($Deleted.Count) owned file(s)."
Write-Output "User-edited/private files were preserved. Empty directories are left in place."
if ($Preserved.Count -gt 0) {
    Write-Output "Skipped during apply:"
    $Preserved | ForEach-Object { Write-Output "  KEEP   $_" }
    Write-Output "Ownership manifest retained for a later cleanup run: $ManifestPath"
}
if ($null -ne $BackupDir) {
    Write-Output "Recovery: copy files back from $BackupDir, then redeploy Rime."
}
