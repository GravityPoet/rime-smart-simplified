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
$Target = [System.IO.Path]::GetFullPath($RimeUserDir)

foreach ($required in @("rime_ice.schema.yaml", "rime_ice.dict.yaml", "rime.lua")) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $required) -PathType Leaf)) {
        throw "Install source is incomplete: missing $required"
    }
}

function Get-RelativePath {
    param([string]$Path)

    return $Path.Substring($Root.Length + 1).Replace("\", "/")
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
if (Test-Path -LiteralPath $SourceGram -PathType Leaf) {
    Write-Output "Grammar model: will copy local $GramFile"
} elseif (Test-Path -LiteralPath $TargetGram -PathType Leaf) {
    Write-Output "Grammar model: already exists at target"
} elseif ($DownloadGram) {
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
if (Test-Path -LiteralPath $SourcePredict -PathType Leaf) {
    Write-Output "Predict data: will copy local $PredictFile"
} elseif (Test-Path -LiteralPath $TargetPredict -PathType Leaf) {
    Write-Output "Predict data: already exists at target"
} elseif ($DownloadPredict) {
    Write-Output "Predict data: will download official librime-predict asset and verify pinned SHA-256"
} else {
    Write-Output "Predict data: skipped by -NoDownloadPredict"
}

if ($DryRun) {
    $Manifest | ForEach-Object { Write-Output $_ }
    exit 0
}

New-Item -ItemType Directory -Force -Path $Target | Out-Null

if (-not $NoBackup) {
    $BackupDir = "$Target.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $BackedUp = $false
    foreach ($relativePath in $Manifest) {
        $destination = Join-Path $Target $relativePath
        if (Test-Path -LiteralPath $destination) {
            if (-not $BackedUp) {
                New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
                $BackedUp = $true
            }
            $backupDestination = Join-Path $BackupDir $relativePath
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backupDestination) | Out-Null
            Copy-Item -LiteralPath $destination -Destination $backupDestination -Force
        }
    }
    if ($BackedUp) {
        Write-Output "Backup: $BackupDir"
    } else {
        Write-Output "Backup: none needed"
    }
} else {
    Write-Output "Backup: skipped by -NoBackup"
}

foreach ($relativePath in $Manifest) {
    $source = Join-Path $Root $relativePath
    $destination = Join-Path $Target $relativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

if (Test-Path -LiteralPath $SourceGram -PathType Leaf) {
    Copy-Item -LiteralPath $SourceGram -Destination $TargetGram -Force
} elseif ((-not (Test-Path -LiteralPath $TargetGram -PathType Leaf)) -and $DownloadGram) {
    $TemporaryGram = "$TargetGram.tmp"
    if (Test-Path -LiteralPath $TemporaryGram) {
        Remove-Item -LiteralPath $TemporaryGram -Force
    }
    try {
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
        Invoke-WebRequest -Uri $GramUrl -OutFile $TemporaryGram
        if ($VerifyGram) {
            $ActualDigest = (Get-FileHash -LiteralPath $TemporaryGram -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($ActualDigest -ne $ExpectedDigest) {
                throw "SHA-256 mismatch for $GramFile. Expected $ExpectedDigest; actual $ActualDigest"
            }
            Write-Output "Verified $GramFile SHA-256: $ActualDigest"
        }
        Move-Item -LiteralPath $TemporaryGram -Destination $TargetGram -Force
    } finally {
        if (Test-Path -LiteralPath $TemporaryGram) {
            Remove-Item -LiteralPath $TemporaryGram -Force
        }
    }
}

if (Test-Path -LiteralPath $SourcePredict -PathType Leaf) {
    Copy-Item -LiteralPath $SourcePredict -Destination $TargetPredict -Force
} elseif ((-not (Test-Path -LiteralPath $TargetPredict -PathType Leaf)) -and $DownloadPredict) {
    $TemporaryPredict = "$TargetPredict.tmp"
    if (Test-Path -LiteralPath $TemporaryPredict) {
        Remove-Item -LiteralPath $TemporaryPredict -Force
    }
    try {
        Write-Output "Downloading $PredictFile ..."
        Invoke-WebRequest -Uri $PredictUrl -OutFile $TemporaryPredict
        $ActualPredictSha = (Get-FileHash -LiteralPath $TemporaryPredict -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($ActualPredictSha -ne $PredictSha256) {
            throw "SHA-256 mismatch for $PredictFile. Expected $PredictSha256; actual $ActualPredictSha"
        }
        Write-Output "Verified $PredictFile SHA-256: $ActualPredictSha"
        Move-Item -LiteralPath $TemporaryPredict -Destination $TargetPredict -Force
    } finally {
        if (Test-Path -LiteralPath $TemporaryPredict) {
            Remove-Item -LiteralPath $TemporaryPredict -Force
        }
    }
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

Write-Output "Installed. Redeploy Rime/Squirrel/Weasel from the input-method menu."
