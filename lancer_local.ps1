# Génère les données ADE puis sert la page sur http://localhost:8765
# Usage : powershell -ExecutionPolicy Bypass -File lancer_local.ps1
Set-Location $PSScriptRoot
$env:PYTHONIOENCODING = "utf-8"
python generer_edt.py
if ($LASTEXITCODE -ne 0) { Write-Warning "Génération en échec : l'ancien data.js (s'il existe) est conservé." }
Start-Process "http://localhost:8765/defilant.html"
python -m http.server 8765 --directory site
