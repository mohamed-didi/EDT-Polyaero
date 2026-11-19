@echo off
rem Lance l affichage EDT : serveur web (port 8765) + mise a jour des donnees toutes les heures.
rem Laisser cette fenetre ouverte (reduite). Page : http://localhost:8765/defilant.html
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
python -m pip install -q requests icalendar tzdata
start "EDT-Serveur" /min python -m http.server 8765 --bind 0.0.0.0 --directory site
:boucle
echo [%date% %time%] Mise a jour des donnees...
python generer_edt.py
timeout /t 3600 /nobreak
goto boucle
