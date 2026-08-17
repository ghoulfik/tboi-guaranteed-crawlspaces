# Copies the mod into Isaac's mods folder without destroying the Workshop link.
#
# Use this instead of copying metadata.xml by hand. Steam records the Workshop
# item id in metadata.xml as <id>, and the in-game uploader decides "update the
# existing item" or "create a brand new one" purely from that value. Overwrite
# the file without carrying the id across and the next upload silently
# publishes a duplicate, leaving the original stranded.
#
# Rules, in order:
#   1. If the repo's metadata.xml carries a real <id>, that wins -- the repo is
#      the source of truth once the id is tracked.
#   2. Otherwise keep whatever id is already installed.
#   3. A real id is never replaced by a missing one, or by the 0 placeholder.
#
# Run:  powershell -ExecutionPolicy Bypass -File tools\install.ps1

#   -Reset    strip the id from both copies, so the next upload CREATES a new
#             item. Needed when the recorded id points at nothing -- the
#             uploader then fails with "Error (9) - File not found", because it
#             is trying to update an item Steam does not have.
#   -Capture  copy the id Steam wrote into the game folder back into the repo.
#             Run this once after the first successful upload.

param(
  [string]$GameDir = "C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth",
  [switch]$Reset,
  [switch]$Capture
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

# The folder name has to match <directory> in metadata.xml, which is what the
# uploader uses to find the mod.
[xml]$meta = Get-Content (Join-Path $root 'metadata.xml') -Raw
$dirName = $meta.metadata.directory
if (-not $dirName) { throw "metadata.xml has no <directory>" }

$dest = Join-Path (Join-Path $GameDir 'mods') $dirName
if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }

function Get-WorkshopId([string]$path) {
  if (-not (Test-Path $path)) { return $null }
  $m = [regex]::Match((Get-Content $path -Raw), '<id>\s*(\d+)\s*</id>')
  if (-not $m.Success) { return $null }
  $id = $m.Groups[1].Value
  # 0 is Isaac's placeholder for "never uploaded", not a real item.
  if ($id -eq '0') { return $null }
  return $id
}

$destMeta = Join-Path $dest 'metadata.xml'
$repoMeta = Join-Path $root 'metadata.xml'
$repoId      = Get-WorkshopId $repoMeta
$installedId = Get-WorkshopId $destMeta

function Set-RepoId([string]$id) {
  $t = Get-Content $repoMeta -Raw
  $t = [regex]::Replace($t, '[ \t]*<id>\s*\d*\s*</id>\r?\n', '')
  if ($id) { $t = $t -replace '</metadata>', "    <id>$id</id>`r`n</metadata>" }
  Set-Content -Path $repoMeta -Value $t -Encoding utf8 -NoNewline
}

if ($Capture) {
  if (-not $installedId) { throw "nothing to capture: the installed metadata.xml has no real <id> yet" }
  Set-RepoId $installedId
  Write-Host "captured workshop id $installedId into the repo"
  $repoId = $installedId
}

if ($Reset) {
  Set-RepoId $null
  $repoId = $null
  $installedId = $null
  Write-Host "workshop id cleared - the next upload will CREATE a new item"
}

$keepId = if ($repoId) { $repoId } else { $installedId }

$xml = Get-Content $repoMeta -Raw

# Normalise: strip any id the repo copy carries, then re-add the one we settled
# on, so the result has exactly one <id> in a predictable place.
$xml = [regex]::Replace($xml, '[ \t]*<id>\s*\d*\s*</id>\r?\n', '')
if ($keepId) {
  $xml = $xml -replace '</metadata>', "    <id>$keepId</id>`r`n</metadata>"
}

Set-Content -Path $destMeta -Value $xml -Encoding utf8 -NoNewline
Copy-Item (Join-Path $root 'main.lua') $dest -Force

# The uploader asks for the preview image through a file dialog that opens in
# the mod folder, so putting a copy there saves hunting for it. Costs subscribers
# ~80 KB and nothing else.
$preview = Join-Path $root 'workshop\preview.png'
if (Test-Path $preview) { Copy-Item $preview $dest -Force }

Write-Host "installed -> $dest"
if ($keepId) {
  $src = if ($repoId) { 'repo' } else { 'existing install' }
  Write-Host "workshop id $keepId preserved (from $src)"
} else {
  Write-Host "no workshop id yet - the next upload will CREATE a new item"
  Write-Host "after publishing, copy the <id> Steam writes back into the repo's metadata.xml"
}
