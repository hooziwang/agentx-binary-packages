param(
  [string]$Dir,
  [switch]$Help
)

$ErrorActionPreference = "Stop"

if ($Help) {
  Write-Output "Install agentx-listing-generation."
  Write-Output ""
  Write-Output "Usage:"
  Write-Output "  install.ps1 [-Dir <path>]"
  exit 0
}

$AppSlug = "agentx-listing-generation"
$BinaryName = "alg.exe"
$PrimaryBase = if ($env:AGENTX_BINARY_RELEASE_PRIMARY_BASE_URL) { $env:AGENTX_BINARY_RELEASE_PRIMARY_BASE_URL } else { "https://raw.githubusercontent.com/hooziwang/agentx-binary-packages/main" }
$FallbackBase = if ($env:AGENTX_BINARY_RELEASE_FALLBACK_BASE_URL) { $env:AGENTX_BINARY_RELEASE_FALLBACK_BASE_URL } else { "https://agentx.aelus.tech/cli" }
$LocalAppData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE "AppData\Local" }
$InstallDir = if ($Dir) { $Dir } else { Join-Path $LocalAppData "AgentXListingGeneration\bin" }

if (-not [Environment]::Is64BitOperatingSystem) {
  throw "agentx-listing-generation installer supports Windows x64 only."
}

function Join-AgentXUrl([string]$Base, [string]$Path) {
  return $Base.TrimEnd("/") + "/" + $Path.TrimStart("/")
}

function Invoke-AgentXJson([string]$Path) {
  foreach ($base in @($PrimaryBase, $FallbackBase)) {
    $url = Join-AgentXUrl $base $Path
    try {
      return Invoke-RestMethod -Uri $url -TimeoutSec 15
    } catch {
      $script:lastJsonError = $_
    }
  }
  throw "Failed to download agentx-listing-generation manifest: $script:lastJsonError"
}

function Save-AgentXDownload([object[]]$Downloads, [string]$OutFile) {
  foreach ($download in @($Downloads)) {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $download.url -OutFile $OutFile -TimeoutSec 600
      return
    } catch {
      $script:lastDownloadError = $_
      Remove-Item -Force $OutFile -ErrorAction SilentlyContinue
    }
  }
  throw "Failed to download agentx-listing-generation binary archive: $script:lastDownloadError"
}

$latest = Invoke-AgentXJson "$AppSlug/latest.json"
$manifestPath = $latest.manifests.windows_amd64
if (-not $manifestPath) { throw "agentx-listing-generation latest manifest is missing windows_amd64." }
$manifest = Invoke-AgentXJson $manifestPath
if (-not $manifest.sha512) { throw "agentx-listing-generation platform manifest is missing sha512." }

$StagingDir = Join-Path $LocalAppData "AgentXListingGeneration\staging"
$ExtractDir = Join-Path $StagingDir "extract"
$ArchivePath = Join-Path $StagingDir "alg.zip"
New-Item -ItemType Directory -Force -Path $StagingDir, $ExtractDir, $InstallDir | Out-Null

Save-AgentXDownload @($manifest.downloads) $ArchivePath
$actualSha512 = (Get-FileHash -Algorithm SHA512 -Path $ArchivePath).Hash.ToLowerInvariant()
if ($actualSha512 -ne $manifest.sha512.ToLowerInvariant()) {
  Remove-Item -Force $ArchivePath -ErrorAction SilentlyContinue
  throw "agentx-listing-generation binary archive SHA512 mismatch."
}

Remove-Item -Recurse -Force $ExtractDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
Expand-Archive -LiteralPath $ArchivePath -DestinationPath $ExtractDir -Force
$Extracted = Join-Path $ExtractDir $BinaryName
if (-not (Test-Path $Extracted)) { throw "agentx-listing-generation archive does not contain $BinaryName." }

$Target = Join-Path $InstallDir $BinaryName
$TempTarget = "$Target.tmp"
Copy-Item -LiteralPath $Extracted -Destination $TempTarget -Force
Move-Item -LiteralPath $TempTarget -Destination $Target -Force
Unblock-File -Path $Target -ErrorAction SilentlyContinue

Write-Output "agentx-listing-generation $($manifest.version) installed at $Target."
