@echo off
:: Configuration pour l'affichage des accents en UTF-8 dans l'invite de commandes
chcp 65001 > nul
setlocal enabledelayedexpansion

set "LOG_FILE=error.log"

echo =================================================================
echo    Assistant de Transcription Audio Universel (Windows Batch)
echo =================================================================

:: -----------------------------------------------------------------
:: 1. VÉRIFICATION ET INSTALLATION DES DÉPENDANCES VIA WINGET
echo 🔍 Vérification des prérequis...

:: FFmpeg
where ffmpeg >nul 2>nul
if %errorlevel% neq 0 (
    echo 🔄 FFmpeg manquant. Installation via Winget...
    winget install --id GNU.FFmpeg -e --silent >> %LOG_FILE% 2>&1
    echo ⚠️ FFmpeg vient d'être installé. Si le script bloque après, redémarrez-le pour actualiser les variables système.
)

:: Python
where python >nul 2>nul
if %errorlevel% neq 0 (
    echo 🔄 Python manquant. Installation de Python 3...
    winget install --id Python.Python.3.11 -e --silent >> %LOG_FILE% 2>&1
    echo ❌ Python a été installé. Vous DEVEZ fermer et rouvrir cette fenêtre pour continuer.
    pause
    exit
)

:: Vérification/Installation de Whisper
pip show openai-whisper >nul 2>nul
if %errorlevel% neq 0 (
    echo 🔄 Installation de OpenAI Whisper via pip...
    pip install -U openai-whisper >> %LOG_FILE% 2>&1
)

echo ✅ Toutes les dépendances sont prêtes.
echo -----------------------------------------------------------------

:: -----------------------------------------------------------------
:: 2. INTERACTION UTILISATEUR (Drag ^& Drop ^+ Options)

echo 📂 Glissez-déposez votre fichier audio ou vidéo ici, puis appuyez sur Entrée :
set /p "RAW_INPUT="

:: Nettoyage des guillemets générés par le glisser-déposer sous Windows
set "CLEANED_PATH=%RAW_INPUT:"=%"

if not exist "%CLEANED_PATH%" (
    echo ❌ Le fichier spécifié n'existe pas : %CLEANED_PATH%
    goto :error_end
)

:: Extraction des informations de dossier et nom
for %%I in ("%CLEANED_PATH%") do (
    set "AUDIO_DIR=%%~dpI"
    set "FILE_NAME=%%~nxI"
    set "FILE_BASE=%%~nI"
)

:: Changement de lecteur et de répertoire vers le dossier de l'audio
cd /d "%AUDIO_DIR%"

:: Sélection du modèle
echo 🤖 Choisissez le modèle Whisper (recommandé : turbo ou medium) :
echo 1] base
echo 2] small
echo 3] medium
echo 4] large-v3-turbo
set /p "MODEL_CHOICE=Votre choix (1-4) [4] : "
set "MODEL=turbo"
if "%MODEL_CHOICE%"=="1" set "MODEL=base"
if "%MODEL_CHOICE%"=="2" set "MODEL=small"
if "%MODEL_CHOICE%"=="3" set "MODEL=medium"

:: Sélection du format
echo 📄 Quel format de transcription souhaitez-vous ?
echo 1] txt (Texte brut)
echo 2] srt (Sous-titres vidéo)
echo 3] json (Données structurées)
echo 4] vtt
set /p "FORMAT_CHOICE=Votre choix (1-4) [1] : "
set "EXPORT_FORMAT=txt"
if "%FORMAT_CHOICE%"=="2" set "EXPORT_FORMAT=srt"
if "%FORMAT_CHOICE%"=="3" set "EXPORT_FORMAT=%EXPORT_FORMAT%"
if "%FORMAT_CHOICE%"=="4" set "EXPORT_FORMAT=vtt"

echo -----------------------------------------------------------------

:: -----------------------------------------------------------------
:: 3. PRÉ-TRAITEMENT AUDIO (Normalisation ^& Conversion)

set "PROCESSED_AUDIO=%FILE_BASE%_normalized.mp3"
echo 🎵 Optimisation de l'audio (Conversion en MP3 Mono 16kHz + Normalisation)...
ffmpeg -y -i "%FILE_NAME%" -af "loudnorm=I=-16:TP=-1.5:LRA=11" -ac 1 -ar 16000 "%PROCESSED_AUDIO%" >> "%AUDIO_DIR%%LOG_FILE%" 2>&1
if %errorlevel% neq 0 goto :error_handler

:: Récupération de la durée via ffprobe
for /f "delims=" %%i in ('ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "%PROCESSED_AUDIO%"') do (
    set "DURATION_RAW=%%i"
)
:: Tronquer la valeur décimale pour le calcul en Batch
for /f "delims=." %%a in ("%DURATION_RAW%") do set "DURATION=%%a"

set "DECOUPAGE=false"
:: 1200 secondes = 20 minutes
if %DURATION% gtr 1200 (
    set /a "DISPLAY_MINS=%DURATION% / 60"
    echo ⏳ Cet audio dure plus de 20 minutes (!DISPLAY_MINS! mins).
    set /p "CHOICE=Voulez-vous le fragmenter par tranches de 20 min pour sécuriser la RAM ? (o/n) [o] : "
    if /i "!CHOICE!"=="n" (
        set "DECOUPAGE=false"
    ) else (
        set "DECOUPAGE=true"
    )
)

:: -----------------------------------------------------------------
:: 4. MOTEUR DE TRANSCRIPTION

set "FINAL_OUTPUT=%FILE_BASE%_Transcription.%EXPORT_FORMAT%"

if "%DECOUPAGE%"=="true" (
    echo ✂️ Découpage de l'audio en segments de 20 minutes...
    set "TMP_DIR=tmp_chunks_%random%"
    mkdir "!TMP_DIR!"
    
    ffmpeg -i "%PROCESSED_AUDIO%" -f segment -segment_time 1200 -c copy "!TMP_DIR!\chunk_%%03d.mp3" >> "%AUDIO_DIR%%LOG_FILE%" 2>&1
    if %errorlevel% neq 0 goto :error_handler

    echo 🚀 Transcription séquentielle des segments...
    cd "!TMP_DIR!"
    
    for %%f in (chunk_*.mp3) do (
        echo --------------------------------------------------
        echo    -^> Traitement actif de : %%f
        echo --------------------------------------------------
        whisper "%%f" --model %MODEL% --language French --output_format %EXPORT_FORMAT%
        if %errorlevel% neq 0 goto :error_handler
    )
    
    echo --------------------------------------------------
    echo 🔗 Fusion et nettoyage des fichiers générés...
    cd ..
    
    :: Recollage des fichiers textes (type équivaut à cat sous Windows)
    type "!TMP_DIR!"\chunk_*.%EXPORT_FORMAT% > "%FINAL_OUTPUT%"
    
    :: Nettoyage du dossier temporaire
    rmdir /s /q "!TMP_DIR!"
) else (
    echo 🚀 Lancement de la transcription globale (Fichier unique)...
    whisper "%PROCESSED_AUDIO%" --model %MODEL% --language French --output_format %EXPORT_FORMAT%
    if %errorlevel% neq 0 goto :error_handler
    move "%FILE_BASE%_normalized.%EXPORT_FORMAT%" "%FINAL_OUTPUT%" >nul
)

:: Nettoyage de l'audio intermédiaire
del /f /q "%PROCESSED_AUDIO%" >nul 2>nul

echo =================================================================
echo 🎉 Opération terminée avec succès !
echo 📄 Votre transcription est prête ici : %AUDIO_DIR%%FINAL_OUTPUT%
echo =================================================================
pause
exit /b 0

:: -----------------------------------------------------------------
:: GESTIONNAIRE D'ERREURS
:error_handler
echo [X] Erreur détectée lors de l'exécution d'une commande système. >> "%AUDIO_DIR%%LOG_FILE%"
echo ❌ Une erreur est survenue. Consultez le fichier %LOG_FILE% dans le dossier de votre audio.
:error_end
pause
exit /b 1