# Builds the POS web app and copies it into backend/public/app, which the
# backend serves at https://<api-host>/app/. Commit backend/public/app and
# push; Render redeploys the backend with the new web app.
#
# Usage (from the mobile folder):  .\build-web.ps1
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

flutter build web --release --base-href /app/ --no-wasm-dry-run
if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }

$target = Join-Path $PSScriptRoot '..\backend\public\app'
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Path $target | Out-Null

# CanvasKit is loaded from Google's CDN (gstatic), so the local copy and the
# build marker are not shipped.
Get-ChildItem 'build\web' -Force |
  Where-Object { $_.Name -notin @('canvaskit', '.last_build_id') } |
  Copy-Item -Destination $target -Recurse

# win_ble (a Windows-only printer dependency) bundles a Windows .exe as an
# asset; it has no use in a browser.
Get-ChildItem $target -Recurse -Filter *.exe | Remove-Item -Force

$size = (Get-ChildItem $target -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
'Web app copied to backend/public/app ({0:N1} MB)' -f $size
