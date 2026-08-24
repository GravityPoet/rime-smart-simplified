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
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$GramFile = "wanxiang-lts-zh-hans.gram"
$PredictFile = "predict.db"

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

$AllowedPaths = @{}
Get-ChildItem -LiteralPath $Root -File -Filter "*.yaml" |
    Where-Object { $_.Name -notin @("user.yaml", "installation.yaml") } |
    ForEach-Object { $AllowedPaths[$_.Name] = $true }
$AllowedPaths["rime.lua"] = $true
$AllowedPaths["custom_phrase.txt"] = $true
$AllowedPaths["smart_chat_phrases.txt"] = $true
foreach ($directory in @("cn_dicts", "cn_dicts_wanxiang", "en_dicts")) {
    $directoryPath = Join-Path $Root $directory
    if (Test-Path -LiteralPath $directoryPath -PathType Container) {
        Get-ChildItem -LiteralPath $directoryPath -File -Recurse |
            Where-Object { $_.Name -like "*.dict.yaml" -or $_.Extension -eq ".txt" } |
            ForEach-Object {
                $AllowedPaths[$_.FullName.Substring($Root.Length + 1).Replace("\", "/")] = $true
            }
    }
}
foreach ($directory in @("lua", "opencc")) {
    $directoryPath = Join-Path $Root $directory
    if (Test-Path -LiteralPath $directoryPath -PathType Container) {
        Get-ChildItem -LiteralPath $directoryPath -File -Recurse |
            Where-Object {
                ($directory -eq "lua" -and $_.Extension -eq ".lua") -or
                ($directory -eq "opencc" -and $_.Extension -in @(".json", ".txt"))
            } |
            ForEach-Object {
                $AllowedPaths[$_.FullName.Substring($Root.Length + 1).Replace("\", "/")] = $true
            }
    }
}
$AllowedPaths[$GramFile] = $true
$AllowedPaths[$PredictFile] = $true
$AllowedPaths[$ManifestName] = $true
$LockPath = Join-Path $Root "UPSTREAM_ASSETS.lock.json"
if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) {
    throw "Upstream asset lock is unavailable; refusing precise uninstall: $LockPath"
}
$UpstreamLock = Get-Content -LiteralPath $LockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$ExpectedGrammarSha = ([string]$UpstreamLock.grammar.digest).Replace("sha256:", "").ToLowerInvariant()
$ExpectedPredictSha = ([string]$UpstreamLock.predict.sha256).ToLowerInvariant()
if ($ExpectedGrammarSha -notmatch '^[0-9a-f]{64}$' -or $ExpectedPredictSha -notmatch '^[0-9a-f]{64}$') {
    throw "Upstream asset lock digests are invalid; refusing precise uninstall."
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

$sourceHashLines = @($lines | Where-Object { $_ -match '^# source_hash=sha256:([0-9a-fA-F]{64})$' })
if ($sourceHashLines.Count -ne 1) {
    throw "Ownership manifest is missing a unique source hash; refusing deletion: $ManifestPath"
}
$expectedSourceHash = ([regex]::Match($sourceHashLines[0], '^# source_hash=sha256:([0-9a-fA-F]{64})$')).Groups[1].Value.ToLowerInvariant()
$SourceRecordLines = New-Object System.Collections.ArrayList

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
    if (-not $AllowedPaths.ContainsKey($relativePath)) {
        throw "Ownership manifest path is not installable by this package; refusing deletion: $relativePath"
    }
    if ($installedSha -notmatch '^[0-9a-f]{64}$' -or $sourceSha -notmatch '^[0-9a-f]{64}$') {
        throw "Invalid ownership digest for: $relativePath"
    }
    if ($ownership -notin @("managed", "asset-created")) {
        throw "Unsupported ownership class for $($relativePath): $ownership"
    }
    if ($installedSha -ne $sourceSha) {
        throw "Ownership manifest source/install digest mismatch; refusing deletion: $relativePath"
    }
    if ($ownership -eq "managed") {
        $sourcePath = Join-Path $Root $relativePath
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Ownership manifest source is unavailable; refusing deletion: $relativePath"
        }
        $expectedSourceSha = Get-Sha256 -Path $sourcePath
    } else {
        switch ($relativePath) {
            $GramFile { $expectedSourceSha = $ExpectedGrammarSha }
            $PredictFile { $expectedSourceSha = $ExpectedPredictSha }
            default { throw "Ownership manifest asset is not pinned; refusing deletion: $relativePath" }
        }
    }
    if ($sourceSha -ne $expectedSourceSha) {
        throw "Ownership manifest source digest does not match the package lock: $relativePath"
    }

    if ($SeenRelativePaths -contains $relativePath) {
        throw "Duplicate ownership manifest entry: $relativePath"
    }
    $SeenRelativePaths += $relativePath
    [void]$SourceRecordLines.Add("$relativePath`t$sourceSha`t$ownership")

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

$sourceRecordPath = [System.IO.Path]::GetTempFileName()
try {
    $utf8NoBom = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    $sourceRecordContent = if ($SourceRecordLines.Count -gt 0) {
        ($SourceRecordLines -join "`n") + "`n"
    } else {
        ""
    }
    [System.IO.File]::WriteAllText($sourceRecordPath, $sourceRecordContent, $utf8NoBom)
    $actualSourceHash = (Get-FileHash -LiteralPath $sourceRecordPath -Algorithm SHA256).Hash.ToLowerInvariant()
} finally {
    Remove-Item -LiteralPath $sourceRecordPath -Force -ErrorAction SilentlyContinue
}
if ($actualSourceHash -ne $expectedSourceHash) {
    throw "Ownership manifest source hash mismatch; refusing deletion: $ManifestPath"
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
        # Record the deletion before invoking Remove-Item. A filesystem
        # operation can remove the directory entry and still throw (for
        # example after an I/O error); keeping it in the recovery list makes
        # that partial delete restorable from the backup.
        [void]$Deleted.Add($candidate.RelativePath)
        Remove-Item -LiteralPath $candidate.Path -Force
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
