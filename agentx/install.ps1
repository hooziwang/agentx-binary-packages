param(
  [string]$Dir,
  [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
  Write-Output "Install AgentX CLI."
  Write-Output ""
  Write-Output "Usage:"
  Write-Output "  install.ps1 [-Dir <path>]"
  exit 0
}

$PrimaryBase = if ($env:AGENTX_BINARY_RELEASE_PRIMARY_BASE_URL) { $env:AGENTX_BINARY_RELEASE_PRIMARY_BASE_URL } else { "https://raw.githubusercontent.com/hooziwang/agentx-binary-packages/main" }
$FallbackBase = if ($env:AGENTX_BINARY_RELEASE_FALLBACK_BASE_URL) { $env:AGENTX_BINARY_RELEASE_FALLBACK_BASE_URL } else { "https://agentx.aelus.tech/cli" }
$LocalAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE "AppData\Local" }
$InstallDir = if ($Dir) { $Dir } else { Join-Path $LocalAppData "AgentX\bin" }

if (-not [Environment]::Is64BitOperatingSystem) {
  throw "AgentX CLI installer supports Windows x64 only."
}

function Join-AgentXUrl([string]$Base, [string]$Path) {
  return $Base.TrimEnd("/") + "/" + $Path.TrimStart("/")
}

function Get-AgentXJsonWithFallback([string]$Path) {
  foreach ($base in @($PrimaryBase, $FallbackBase)) {
    $url = Join-AgentXUrl $base $Path
    try {
      return Invoke-RestMethod -Uri $url -UseBasicParsing -TimeoutSec 60
    } catch {
      $script:lastJsonError = $_
    }
  }
  throw "Failed to download AgentX manifest: $script:lastJsonError"
}

function Get-AgentXSha512([string]$Path) {
  try {
    return (Get-FileHash -Algorithm SHA512 -Path $Path).Hash.ToLowerInvariant()
  } catch {
    $certutil = & certutil -hashfile $Path SHA512
    if ($LASTEXITCODE -ne 0) { throw "Failed to calculate SHA512 for $Path" }
    return (($certutil | Where-Object { $_ -match "^[A-Fa-f0-9]{128}$" } | Select-Object -First 1).Trim().ToLowerInvariant())
  }
}

function Save-AgentXDownload([object[]]$Downloads, [string]$OutFile) {
  foreach ($download in @($Downloads)) {
    try {
      Invoke-WebRequest -Uri $download.url -OutFile $OutFile -UseBasicParsing -TimeoutSec 600
      return
    } catch {
      $script:lastDownloadError = $_
    }
  }
  throw "Failed to download AgentX binary archive: $script:lastDownloadError"
}

$latest = Get-AgentXJsonWithFallback "agentx/latest.json"
$manifestPath = $latest.manifests.windows_amd64
if (-not $manifestPath) { throw "AgentX latest manifest is missing windows_amd64." }
$manifest = Get-AgentXJsonWithFallback $manifestPath
if (-not $manifest.sha512) { throw "AgentX platform manifest is missing sha512." }

$StagingDir = Join-Path $LocalAppData "AgentX\staging"
$ExtractDir = Join-Path $StagingDir "extract"
$ArchivePath = Join-Path $StagingDir "agentx.zip"
New-Item -ItemType Directory -Force -Path $StagingDir, $ExtractDir, $InstallDir | Out-Null

Save-AgentXDownload @($manifest.downloads) $ArchivePath
$actualSha512 = Get-AgentXSha512 $ArchivePath
if ($actualSha512 -ne $manifest.sha512.ToLowerInvariant()) {
  Remove-Item -Force $ArchivePath -ErrorAction SilentlyContinue
  throw "AgentX binary archive SHA512 mismatch."
}

Remove-Item -Recurse -Force $ExtractDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
Expand-Archive -LiteralPath $ArchivePath -DestinationPath $ExtractDir -Force
$Extracted = Join-Path $ExtractDir "agentx.exe"
if (-not (Test-Path $Extracted)) { throw "AgentX archive does not contain agentx.exe." }

$Target = Join-Path $InstallDir "agentx.exe"
$TempTarget = "$Target.tmp"
Copy-Item -LiteralPath $Extracted -Destination $TempTarget -Force
Move-Item -LiteralPath $TempTarget -Destination $Target -Force
Unblock-File -Path $Target -ErrorAction SilentlyContinue

& $Target install --dir $InstallDir
Write-Output "AgentX $($manifest.version) installed at $Target."
