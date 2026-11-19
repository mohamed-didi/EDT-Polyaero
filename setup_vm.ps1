# Installation de l'affichage EDT sur la VM Windows (à lancer UNE fois, en administrateur).
#
#   powershell -ExecutionPolicy Bypass -File setup_vm.ps1
#
# Ce script :
#   1. vérifie Python et installe les dépendances (requests, icalendar, tzdata)
#   2. génère une première fois site\data.js
#   3. crée 2 tâches planifiées (sous votre compte, sans mot de passe) :
#        - EDT-Serveur     : sert le dossier site\ sur le port 8765 au démarrage de la VM
#        - EDT-MiseAJour   : relance generer_edt.py chaque jour à 06:00 et au démarrage
#   4. ouvre le port 8765 dans le pare-feu Windows
#   5. affiche l'adresse à ouvrir sur la TV

$ErrorActionPreference = "Stop"
$Port = 8765
$Heure = "06:00"
$Dossier = $PSScriptRoot

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Relancez ce script dans un PowerShell ouvert en tant qu'administrateur."
}

# --- 1. Python ---------------------------------------------------------------
$python = (& where.exe python 2>$null | Where-Object { $_ -notmatch "WindowsApps" } | Select-Object -First 1)
if (-not $python) {
    Write-Host "Python introuvable : installation via winget..."
    winget install -e --id Python.Python.3.12 --accept-package-agreements --accept-source-agreements
    $python = (& where.exe python 2>$null | Where-Object { $_ -notmatch "WindowsApps" } | Select-Object -First 1)
    if (-not $python) { throw "Python vient d'être installé : fermez ce PowerShell, rouvrez-le (admin) et relancez le script." }
}
Write-Host "Python : $python"
& $python -m pip install --quiet --upgrade requests icalendar tzdata
if ($LASTEXITCODE -ne 0) { throw "Échec de l'installation des dépendances Python." }

# --- 2. Première génération -------------------------------------------------
Set-Location $Dossier
$env:PYTHONIOENCODING = "utf-8"
& $python generer_edt.py
if ($LASTEXITCODE -ne 0) { Write-Warning "Première génération en échec (ADE injoignable ?). Les tâches réessaieront." }

# --- 3. Tâches planifiées ----------------------------------------------------
$utilisateur = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $utilisateur -LogonType S4U -RunLevel Highest
$reglages = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)

# Serveur web (démarrage de la VM)
$actionServeur = New-ScheduledTaskAction -Execute $python `
    -Argument "-m http.server $Port --bind 0.0.0.0 --directory `"$Dossier\site`"" -WorkingDirectory $Dossier
Register-ScheduledTask -TaskName "EDT-Serveur" -Force -Principal $principal -Settings $reglages `
    -Action $actionServeur -Trigger (New-ScheduledTaskTrigger -AtStartup) | Out-Null

# Mise à jour des données (chaque jour + au démarrage)
$actionMaj = New-ScheduledTaskAction -Execute "powershell.exe" -WorkingDirectory $Dossier `
    -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"`$env:PYTHONIOENCODING='utf-8'; & '$python' generer_edt.py *>> '$Dossier\maj.log'`""
$declencheurs = @(
    (New-ScheduledTaskTrigger -Daily -At $Heure),
    (New-ScheduledTaskTrigger -AtStartup)
)
$declencheurs[1].Delay = "PT2M"   # laisse le temps au réseau de démarrer
Register-ScheduledTask -TaskName "EDT-MiseAJour" -Force -Principal $principal -Settings $reglages `
    -Action $actionMaj -Trigger $declencheurs | Out-Null

# --- 4. Pare-feu -------------------------------------------------------------
if (-not (Get-NetFirewallRule -DisplayName "EDT-Affichage" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "EDT-Affichage" -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Any | Out-Null
}

# --- 5. Démarrage immédiat + adresse -----------------------------------------
Stop-ScheduledTask -TaskName "EDT-Serveur" -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName "EDT-Serveur"
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "Installation terminée." -ForegroundColor Green
Write-Host "Adresse(s) à ouvrir sur la TV :"
Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notmatch "^(127|169\.254)" } |
    ForEach-Object { Write-Host ("  http://{0}:{1}/defilant.html" -f $_.IPAddress, $Port) }
Write-Host ""
Write-Host "Mise à jour des données : tous les jours à $Heure et au démarrage (journal : $Dossier\maj.log)."
