[CmdletBinding()]
param(
    [string]$RimeUserDir = "",
    [switch]$DryRun,
    [switch]$NoBackup,
    [switch]$NoDownloadGram,
    [switch]$SkipVerifyGram,
    [switch]$NoDownloadPredict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Windows PowerShell 5.1 may still default to TLS 1.0/1.1. GitHub requires
# TLS 1.2; setting this is harmless under PowerShell 7 (which uses its own
# HTTP stack) and keeps the legacy entry point usable on supported Windows.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch {
    # PowerShell 7 can ignore ServicePointManager when using HttpClient.
}

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$GramFile = "wanxiang-lts-zh-hans.gram"
$GramUrl = "https://github.com/amzxyz/RIME-LMDG/releases/download/LTS/wanxiang-lts-zh-hans.gram"
$GramApiUrl = "https://api.github.com/repos/amzxyz/RIME-LMDG/releases/tags/LTS"
# librime-predict official data (Traditional Chinese; the schema converts
# predictions to Simplified via prediction_simplify). The release is old and
# has no GitHub digest, so we pin a known SHA-256.
$PredictFile = "predict.db"
$PredictUrl = "https://github.com/rime/librime-predict/releases/download/data-1.0/predict.db"
$PredictSha256 = "2a5a2b7c77f8f3d7c0836dfc8fd8b791ac2574d8bd93a3a2baaae1ee4861f5be"
$InstallManifestName = ".rime-smart-simplified.install-manifest"
$PrivateStateFiles = @(
    "lua/cold_word_drop/drop_words.lua",
    "lua/cold_word_drop/hide_words.lua",
    "lua/cold_word_drop/reduce_freq_words.lua"
)

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

$Target = Normalize-FullPath -Path $RimeUserDir
$MarkerPath = Join-Path $Target $InstallManifestName

foreach ($required in @("rime_ice.schema.yaml", "rime_ice.dict.yaml", "rime.lua")) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $required) -PathType Leaf)) {
        throw "Install source is incomplete: missing $required"
    }
}

function Get-RelativePath {
    param([string]$Path)

    return $Path.Substring($Root.Length + 1).Replace("\", "/")
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

function Write-Utf8NoBom {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    # Set-Content -Encoding UTF8 emits a BOM on Windows PowerShell 5.1.
    # Keep the ownership manifest readable by the POSIX uninstall path too.
    $encoding = New-Object -TypeName System.Text.UTF8Encoding -ArgumentList $false
    $content = if ($null -ne $Lines -and $Lines.Count -gt 0) {
        ($Lines -join "`n") + "`n"
    } else {
        ""
    }
    [System.IO.File]::WriteAllText($Path, $content, $encoding)
}

function Assert-SafeManifestValue {
    param(
        [string]$Value,
        [string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -notmatch '^[A-Za-z0-9._:+/@=-]+$') {
        throw "$Label contains characters that cannot be represented safely in the ownership manifest."
    }
}

function Test-HardLink {
    param(
        [object]$Item,
        [string]$Path
    )

    $linkTypeProperty = $Item.PSObject.Properties["LinkType"]
    if ($null -ne $linkTypeProperty -and [string]$Item.LinkType -eq "HardLink") {
        return $true
    }

    # Windows PowerShell 5.1 does not expose LinkType consistently. fsutil is
    # built into supported Windows versions and reports every directory entry
    # sharing the same NTFS file record.
    if ($env:OS -eq "Windows_NT") {
        $fsutil = Get-Command fsutil.exe -ErrorAction SilentlyContinue
        if ($null -ne $fsutil) {
            $hardlinkLines = @(& $fsutil.Source hardlink list $Path 2>$null | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $fsutilStatus = $LASTEXITCODE
            if ($fsutilStatus -eq 0 -and $hardlinkLines.Count -gt 1) {
                return $true
            }
        }
    }
    return $false
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

function Assert-NoReparsePointBelowTarget {
    param(
        [string]$DestinationPath,
        [string]$TargetRoot
    )

    $targetFull = Normalize-FullPath -Path $TargetRoot
    $current = Normalize-FullPath -Path $DestinationPath
    while (-not [string]::Equals(
        $current,
        $targetFull,
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        $item = Get-ExistingItem -Path $current
        if ($null -ne $item) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to write through a symlink or junction below the Rime target: $current"
            }
        }

        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) {
            throw "Install destination is not contained by the Rime target: $DestinationPath"
        }
        $current = Normalize-FullPath -Path $parent
    }
}

function Get-PackageVersion {
    if (-not [string]::IsNullOrWhiteSpace($env:RIME_PACKAGE_VERSION)) {
        return $env:RIME_PACKAGE_VERSION
    }
    try {
        $value = (& git -C $Root describe --tags --always 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
    } catch {
        # Release archives do not include .git; metadata remains explicit below.
    }
    return "unknown"
}

function Get-SourceRevision {
    try {
        $value = (& git -C $Root rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
    } catch {
        # Release archives do not include .git.
    }
    return "unknown"
}

$Manifest = @()
$Manifest += Get-ChildItem -LiteralPath $Root -File -Filter "*.yaml" |
    Where-Object { $_.Name -notin @("user.yaml", "installation.yaml") } |
    ForEach-Object { $_.Name }
$Manifest += "rime.lua"

$CustomPhraseTarget = Join-Path $Target "custom_phrase.txt"
if (-not (Test-Path -LiteralPath $CustomPhraseTarget)) {
    $Manifest += "custom_phrase.txt"
}

$ChatPhrasesTarget = Join-Path $Target "smart_chat_phrases.txt"
if (-not (Test-Path -LiteralPath $ChatPhrasesTarget)) {
    $Manifest += "smart_chat_phrases.txt"
}

foreach ($directory in @("cn_dicts", "cn_dicts_wanxiang", "en_dicts")) {
    $Manifest += Get-ChildItem -LiteralPath (Join-Path $Root $directory) -File -Recurse |
        Where-Object { $_.Name -like "*.dict.yaml" -or $_.Extension -eq ".txt" } |
        ForEach-Object { Get-RelativePath -Path $_.FullName }
}

$Manifest += Get-ChildItem -LiteralPath (Join-Path $Root "lua") -File -Filter "*.lua" -Recurse |
    ForEach-Object { Get-RelativePath -Path $_.FullName } |
    Where-Object {
        $relativePath = $_
        ($relativePath -notin $PrivateStateFiles) -or
            (-not (Test-Path -LiteralPath (Join-Path $Target $relativePath)))
    }

$Manifest += Get-ChildItem -LiteralPath (Join-Path $Root "opencc") -File -Recurse |
    Where-Object { $_.Extension -in @(".json", ".txt") } |
    ForEach-Object { Get-RelativePath -Path $_.FullName }

$Manifest = @($Manifest | Sort-Object -Unique)
$DownloadGram = -not $NoDownloadGram
$VerifyGram = -not $SkipVerifyGram
$DownloadPredict = -not $NoDownloadPredict

Write-Output "Target: $Target"
Write-Output "Backup decision: overwrite-capable local config install; backup is enabled by default."
Write-Output "Files to install: $($Manifest.Count)"
if (Test-Path -LiteralPath $CustomPhraseTarget) {
    Write-Output "Private phrases: preserving existing custom_phrase.txt"
} else {
    Write-Output "Private phrases: installing the public custom_phrase.txt template"
}
if ($PrivateStateFiles | Where-Object { Test-Path -LiteralPath (Join-Path $Target $_) }) {
    Write-Output "Cold-word preferences: preserving existing hide/drop/reduce records"
} else {
    Write-Output "Cold-word preferences: installing empty templates"
}

$SourceGram = Join-Path $Root $GramFile
$TargetGram = Join-Path $Target $GramFile
$NeedGramDownload = (
    (-not (Test-Path -LiteralPath $SourceGram -PathType Leaf)) -and
    (-not (Test-Path -LiteralPath $TargetGram -PathType Leaf)) -and
    $DownloadGram
)
if (Test-Path -LiteralPath $SourceGram -PathType Leaf) {
    Write-Output "Grammar model: will copy local $GramFile"
} elseif (Test-Path -LiteralPath $TargetGram -PathType Leaf) {
    Write-Output "Grammar model: already exists at target"
} elseif ($NeedGramDownload) {
    if ($VerifyGram) {
        Write-Output "Grammar model: will download official RIME-LMDG LTS asset and verify GitHub Release SHA-256 digest"
    } else {
        Write-Output "Grammar model: will download official RIME-LMDG LTS asset without digest verification"
    }
} else {
    Write-Output "Grammar model: skipped by -NoDownloadGram"
}

$SourcePredict = Join-Path $Root $PredictFile
$TargetPredict = Join-Path $Target $PredictFile
$NeedPredictDownload = (
    (-not (Test-Path -LiteralPath $SourcePredict -PathType Leaf)) -and
    (-not (Test-Path -LiteralPath $TargetPredict -PathType Leaf)) -and
    $DownloadPredict
)
if (Test-Path -LiteralPath $SourcePredict -PathType Leaf) {
    Write-Output "Predict data: will copy local $PredictFile"
} elseif (Test-Path -LiteralPath $TargetPredict -PathType Leaf) {
    Write-Output "Predict data: already exists at target"
} elseif ($NeedPredictDownload) {
    Write-Output "Predict data: will download official librime-predict asset and verify pinned SHA-256"
} else {
    Write-Output "Predict data: skipped by -NoDownloadPredict"
}

if ($DryRun) {
    $Manifest | ForEach-Object { Write-Output $_ }
    exit 0
}

$StagingDir = $null
$StagedGram = $null
$StagedPredict = $null
$RollbackDir = $null
$KeepRollbackDir = $false

try {
    $StagingDir = Join-Path ([System.IO.Path]::GetTempPath()) (
        "rime-smart-simplified-stage-" + [System.Guid]::NewGuid().ToString("N")
    )
    New-Item -ItemType Directory -Path $StagingDir -ErrorAction Stop | Out-Null

    if ($NeedGramDownload) {
        $StagedGram = Join-Path $StagingDir $GramFile
        $ExpectedDigest = ""
        if ($VerifyGram) {
            $Release = Invoke-RestMethod -Uri $GramApiUrl
            $Asset = $Release.assets | Where-Object { $_.name -eq $GramFile } | Select-Object -First 1
            if ($null -eq $Asset -or [string]::IsNullOrWhiteSpace($Asset.digest)) {
                throw "Could not read GitHub Release SHA-256 digest for $GramFile"
            }
            if (-not $Asset.digest.StartsWith("sha256:")) {
                throw "Unsupported GitHub asset digest for $GramFile`: $($Asset.digest)"
            }
            $ExpectedDigest = $Asset.digest.Substring(7).ToLowerInvariant()
        }

        Write-Output "Downloading $GramFile ..."
            Invoke-WebRequest -Uri $GramUrl -OutFile $StagedGram -UseBasicParsing
        if ($VerifyGram) {
            $ActualDigest = (Get-FileHash -LiteralPath $StagedGram -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($ActualDigest -ne $ExpectedDigest) {
                throw "SHA-256 mismatch for $GramFile. Expected $ExpectedDigest; actual $ActualDigest"
            }
            Write-Output "Verified $GramFile SHA-256: $ActualDigest"
        }
    }

    if ($NeedPredictDownload) {
        $StagedPredict = Join-Path $StagingDir $PredictFile
        Write-Output "Downloading $PredictFile ..."
        Invoke-WebRequest -Uri $PredictUrl -OutFile $StagedPredict -UseBasicParsing
        $ActualPredictSha = (Get-FileHash -LiteralPath $StagedPredict -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($ActualPredictSha -ne $PredictSha256) {
            throw "SHA-256 mismatch for $PredictFile. Expected $PredictSha256; actual $ActualPredictSha"
        }
        Write-Output "Verified $PredictFile SHA-256: $ActualPredictSha"
    }

    $WriteEntries = @()
    foreach ($relativePath in $Manifest) {
        $WriteEntries += [PSCustomObject]@{
            RelativePath = $relativePath
            SourcePath = Join-Path $Root $relativePath
            DestinationPath = Join-Path $Target $relativePath
            OriginallyExisted = $false
            Ownership = "managed"
        }
    }

    if (Test-Path -LiteralPath $SourceGram -PathType Leaf) {
        $WriteEntries += [PSCustomObject]@{
            RelativePath = $GramFile
            SourcePath = $SourceGram
            DestinationPath = $TargetGram
            OriginallyExisted = $false
            Ownership = "asset-created"
        }
    } elseif ($NeedGramDownload) {
        $WriteEntries += [PSCustomObject]@{
            RelativePath = $GramFile
            SourcePath = $StagedGram
            DestinationPath = $TargetGram
            OriginallyExisted = $false
            Ownership = "asset-created"
        }
    }

    if (Test-Path -LiteralPath $SourcePredict -PathType Leaf) {
        $WriteEntries += [PSCustomObject]@{
            RelativePath = $PredictFile
            SourcePath = $SourcePredict
            DestinationPath = $TargetPredict
            OriginallyExisted = $false
            Ownership = "asset-created"
        }
    } elseif ($NeedPredictDownload) {
        $WriteEntries += [PSCustomObject]@{
            RelativePath = $PredictFile
            SourcePath = $StagedPredict
            DestinationPath = $TargetPredict
            OriginallyExisted = $false
            Ownership = "asset-created"
        }
    }

    foreach ($entry in $WriteEntries) {
        Assert-NoReparsePointBelowTarget -DestinationPath $entry.DestinationPath -TargetRoot $Target
    }

    foreach ($entry in $WriteEntries) {
        $existingItem = Get-ExistingItem -Path $entry.DestinationPath
        if ($null -ne $existingItem) {
            if (($existingItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to overwrite a symlink or junction below the Rime target: $($entry.DestinationPath)"
            }
            if ($existingItem.PSIsContainer) {
                throw "Refusing to overwrite a non-regular install destination: $($entry.DestinationPath)"
            }
            if (Test-HardLink -Item $existingItem -Path $entry.DestinationPath) {
                throw "Refusing to overwrite a hard-linked file below the Rime target; replace it first to protect external paths: $($entry.DestinationPath)"
            }
            $entry.OriginallyExisted = $true
        } else {
            $entry.OriginallyExisted = $false
        }
    }

    Assert-NoReparsePointBelowTarget -DestinationPath $MarkerPath -TargetRoot $Target
    $markerItem = Get-ExistingItem -Path $MarkerPath
    if ($null -ne $markerItem -and ($markerItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to overwrite a symlink or junction below the Rime target: $MarkerPath"
    }
    if ($null -ne $markerItem -and $markerItem.PSIsContainer) {
        throw "Refusing to overwrite a non-regular install manifest: $MarkerPath"
    }
    if ($null -ne $markerItem -and (Test-HardLink -Item $markerItem -Path $MarkerPath)) {
        throw "Refusing to overwrite a hard-linked install manifest; replace it first to protect external paths: $MarkerPath"
    }

    $SourceRecordLines = @()
    $ManifestEntryLines = @()
    foreach ($entry in $WriteEntries) {
        if ($entry.Ownership -eq "asset-created" -and $entry.OriginallyExisted) {
            continue
        }
        $sourceDigest = (Get-FileHash -LiteralPath $entry.SourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $SourceRecordLines += "$($entry.RelativePath)`t$sourceDigest`t$($entry.Ownership)"
        $ManifestEntryLines += "file`t$($entry.RelativePath)`t$sourceDigest`t$sourceDigest`t$($entry.Ownership)"
    }
    $SourceRecordsPath = Join-Path $StagingDir "source-records"
    Write-Utf8NoBom -Path $SourceRecordsPath -Lines $SourceRecordLines
    $SourceTreeHash = (Get-FileHash -LiteralPath $SourceRecordsPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $PackageVersion = Get-PackageVersion
    $SourceRevision = Get-SourceRevision
    Assert-SafeManifestValue -Value $PackageVersion -Label "RIME_PACKAGE_VERSION"
    Assert-SafeManifestValue -Value $SourceRevision -Label "SOURCE_REVISION"
    $StagedManifest = Join-Path $StagingDir $InstallManifestName
    $ManifestLines = @(
        "# rime-smart-simplified install manifest v2"
        "# Generated by scripts/install.ps1; do not edit."
        "# package_version=$PackageVersion"
        "# source_revision=$SourceRevision"
        "# source_hash=sha256:$SourceTreeHash"
        $ManifestEntryLines
    )
    Write-Utf8NoBom -Path $StagedManifest -Lines $ManifestLines
    $markerOriginallyExisted = $null -ne $markerItem
    $WriteEntries += [PSCustomObject]@{
        RelativePath = $InstallManifestName
        SourcePath = $StagedManifest
        DestinationPath = $MarkerPath
        OriginallyExisted = $markerOriginallyExisted
        Ownership = "managed"
    }
    $ExistingEntries = @($WriteEntries | Where-Object { $_.OriginallyExisted })

    $BackupDir = $null
    if (-not $NoBackup) {
        if ($ExistingEntries.Count -gt 0) {
            $BackupBase = "$Target.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            $BackupDir = New-UniqueBackupDirectory -BasePath $BackupBase
            foreach ($entry in $ExistingEntries) {
                $backupDestination = Join-Path $BackupDir $entry.RelativePath
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupDestination) | Out-Null
                Copy-Item -LiteralPath $entry.DestinationPath -Destination $backupDestination -Force
            }
            Write-Output "Backup: $BackupDir"
        } else {
            Write-Output "Backup: none needed"
        }
    } else {
        Write-Output "Backup: skipped by -NoBackup"
    }

    $RecoverySourceDir = $BackupDir
    if ($NoBackup -and $ExistingEntries.Count -gt 0) {
        $RollbackDir = Join-Path ([System.IO.Path]::GetTempPath()) (
            "rime-smart-simplified-rollback-" + [System.Guid]::NewGuid().ToString("N")
        )
        New-Item -ItemType Directory -Path $RollbackDir -ErrorAction Stop | Out-Null
        foreach ($entry in $ExistingEntries) {
            $rollbackDestination = Join-Path $RollbackDir $entry.RelativePath
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $rollbackDestination) | Out-Null
            Copy-Item -LiteralPath $entry.DestinationPath -Destination $rollbackDestination -Force
        }
        $RecoverySourceDir = $RollbackDir
    }

    $TouchedEntries = @()
    $TargetOriginallyExisted = $null -ne (Get-ExistingItem -Path $Target)
    try {
        New-Item -ItemType Directory -Force -Path $Target | Out-Null

        foreach ($entry in $WriteEntries) {
            $TouchedEntries += $entry
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $entry.DestinationPath) | Out-Null
            Copy-Item -LiteralPath $entry.SourcePath -Destination $entry.DestinationPath -Force
        }

        foreach ($required in @(
            "rime_ice.schema.yaml",
            "rime_ice.dict.yaml",
            "rime.lua",
            "custom_phrase.txt",
            "smart_chat_phrases.txt",
            "lua/cold_word_drop/drop_words.lua",
            "lua/cold_word_drop/hide_words.lua",
            "lua/cold_word_drop/reduce_freq_words.lua"
        )) {
            if (-not (Test-Path -LiteralPath (Join-Path $Target $required) -PathType Leaf)) {
                throw "Installation verification failed: missing $required"
            }
        }
        if ($DownloadGram -and -not (Test-Path -LiteralPath $TargetGram -PathType Leaf)) {
            throw "Installation verification failed: missing $GramFile"
        }
        if ($DownloadPredict -and -not (Test-Path -LiteralPath $TargetPredict -PathType Leaf)) {
            throw "Installation verification failed: missing $PredictFile"
        }
    } catch {
        $InstallFailure = $_
        $RecoveryErrors = @()

        foreach ($entry in $TouchedEntries) {
            try {
                if ($entry.OriginallyExisted) {
                    $recoverySource = Join-Path $RecoverySourceDir $entry.RelativePath
                    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $entry.DestinationPath) | Out-Null
                    Copy-Item -LiteralPath $recoverySource -Destination $entry.DestinationPath -Force
                } elseif (Test-Path -LiteralPath $entry.DestinationPath) {
                    Remove-Item -LiteralPath $entry.DestinationPath -Force
                }
            } catch {
                $RecoveryErrors += "$($entry.RelativePath): $($_.Exception.Message)"
            }
        }

        if ($RecoveryErrors.Count -eq 0 -and -not $TargetOriginallyExisted -and (Test-Path -LiteralPath $Target)) {
            try {
                Remove-Item -LiteralPath $Target -Recurse -Force
            } catch {
                $RecoveryErrors += "target directory: $($_.Exception.Message)"
            }
        }

        if ($RecoveryErrors.Count -eq 0 -and $TouchedEntries.Count -eq 0) {
            $RecoverySummary = "succeeded; no target files required recovery"
        } elseif ($RecoveryErrors.Count -eq 0) {
            $RecoverySummary = "succeeded; overwritten files restored and new files removed"
        } else {
            $RecoverySummary = "INCOMPLETE: $($RecoveryErrors -join '; ')"
            if ($null -ne $RollbackDir) {
                $KeepRollbackDir = $true
            }
        }

        if ($null -ne $BackupDir) {
            $BackupSummary = $BackupDir
        } elseif ($KeepRollbackDir) {
            $BackupSummary = "$RollbackDir (temporary rollback snapshot retained)"
        } elseif ($NoBackup) {
            $BackupSummary = "none (-NoBackup)"
        } else {
            $BackupSummary = "none needed"
        }

        throw "Installation failed: $($InstallFailure.Exception.Message) Recovery: $RecoverySummary. Backup: $BackupSummary"
    }

    Write-Output "Installed. Redeploy Rime/Squirrel/Weasel from the input-method menu."
} finally {
    if ($null -ne $StagingDir -and (Test-Path -LiteralPath $StagingDir)) {
        Remove-Item -LiteralPath $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $RollbackDir -and -not $KeepRollbackDir -and (Test-Path -LiteralPath $RollbackDir)) {
        Remove-Item -LiteralPath $RollbackDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
