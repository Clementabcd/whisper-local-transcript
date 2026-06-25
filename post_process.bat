@echo off
:: Configuration pour l'affichage des accents en UTF-8 dans l'invite de commandes
chcp 65001 > nul
setlocal enabledelayedexpansion

set "LOG_FILE=post_process_error.log"

echo =================================================================
echo    Assistant de Post-Traitement LLM Local (Windows Batch)
echo =================================================================

:: -----------------------------------------------------------------
:: 1. VÉRIFICATION ET CONFIGURATION OLLAMA
where ollama >nul 2>nul
if %errorlevel% neq 0 (
    echo 🔄 Ollama n'est pas détecté. Tentative d'installation via Winget...
    winget install --id Ollama.Ollama -e --silent >> %LOG_FILE% 2>&1
    echo ❌ Ollama a été installé. Vous DEVEZ fermer et rouvrir cette fenêtre pour continuer.
    pause
    exit
)

:: -----------------------------------------------------------------
:: 2. SÉLECTION DU MODÈLE DE LANGAGE
echo 🤖 Choisissez le modèle LLM local à utiliser :
echo 1] Gemma 2 (2B) - ~1.6 Go [Par défaut, ultra-rapide]
echo 2] Gemma 2 (9B) - ~5.5 Go [Très performant]
echo 3] Qwen 2.5 (1.5B) - ~980 Mo [Ultra-léger]
echo 4] Qwen 2.5 (7B) - ~4.7 Go [Excellent en synthèse/tableaux]
echo 5] Llama 3.1 (8B) - ~4.7 Go [Trilingue et robuste, recommandé]
echo 6] Mistral (7B) - ~4.1 Go [Référence francophone]
set /p "MODEL_CHOICE=Votre choix (1-6) [1] : "

set "MODEL_NAME=gemma2:2b"
if "%MODEL_CHOICE%"=="2" set "MODEL_NAME=gemma2:9b"
if "%MODEL_CHOICE%"=="3" set "MODEL_NAME=qwen2.5:1.5b"
if "%MODEL_CHOICE%"=="4" set "MODEL_NAME=qwen2.5:7b"
if "%MODEL_CHOICE%"=="5" set "MODEL_NAME=llama3.1:8b"
if "%MODEL_CHOICE%"=="6" set "MODEL_NAME=mistral:7b"

echo 🔄 Vérification de la présence du modèle (!MODEL_NAME!)...
ollama list | findstr /I "!MODEL_NAME!" >nul
if %errorlevel% neq 0 (
    echo 📥 Téléchargement du modèle !MODEL_NAME! (cette étape ne se produit qu'une seule fois)...
    ollama pull !MODEL_NAME!
)

echo ✅ Le modèle !MODEL_NAME! est prêt.
echo -----------------------------------------------------------------

:: -----------------------------------------------------------------
:: 3. SÉLECTION DE LA TRANSCRIPTION BRUTE
echo 📂 Glissez-déposez votre fichier de transcription (.txt ou .json) ici, puis appuyez sur Entrée :
set /p "RAW_INPUT="

:: Nettoyage des guillemets Windows
set "TRANSCRIPTION_PATH=%RAW_INPUT:"=%"

if not exist "%TRANSCRIPTION_PATH%" (
    echo ❌ Le fichier spécifié n'existe pas : %TRANSCRIPTION_PATH%
    pause
    exit
)

:: Extraction des variables de dossier et noms
for %%I in ("%TRANSCRIPTION_PATH%") do (
    set "DIR_PATH=%%~dpI"
    set "FILE_BASE=%%~nI"
)

:: -----------------------------------------------------------------
:: 4. CHOIX DE LA LANGUE DE SORTIE
echo 🌐 Dans quelle langue souhaitez-vous obtenir le résultat ?
set /p "TARGET_LANG=Langue (ex: Français, Anglais, Espagnol...) [Français] : "
if "%TARGET_LANG%"=="" set "TARGET_LANG=Français"

:: -----------------------------------------------------------------
:: 5. BOUCLE PRINCIPALE D'ACTIONS
:main_loop
echo -----------------------------------------------------------------
echo ✨ Quelle action souhaitez-vous effectuer sur cette transcription ?
echo 1] 📝 Transcription intégrale fluidifiée (Garder 100%% du texte original, corriger fautes/tics)
echo 2] 📊 Résumé exécutif complet (Résumé + Points clés + Actions 'Qui fait quoi')
echo 3] 🧱 Synthèse sous forme de Tableau structurel
echo 4] 🧠 Explication pédagogique / Analyse des points complexes
echo 5] ✍️ Prompt personnalisé (Saisissez votre propre consigne)
echo 6] ❌ Quitter le script
set /p "USER_CHOICE=Votre choix (1-6) : "

if "%USER_CHOICE%"=="6" (
    echo 👋 Au revoir !
    pause
    exit /b 0
)

set "SYSTEM_PROMPT=Tu es un secrétaire de direction expert. Tu dois rédiger TOUTES tes réponses uniquement en %TARGET_LANG%. Interdiction absolue d'utiliser l'anglais. Tu parles directement du fond de la réunion, sans jamais dire 'la transcription parle de' ou 'ce document montre que'."

if "%USER_CHOICE%"=="1" (
    set "MODIFIER=MISSION : Agis comme un correcteur d'orthographe et de grammaire textuel. Tu dois réécrire TOUT le texte fourni, mot à mot, du début à la fin. Interdiction absolue de résumer, de condenser ou de couper des paragraphes. Nettoie uniquement les tics de langage oraux ('euh', 'du coup', 'en fait') et corrige les fautes de grammaire. Restitue 100%% du texte d'origine nettoyé en %TARGET_LANG%."
    set "SUFFIX=_TexteIntegral"
) else if "%USER_CHOICE%"=="2" (
    set "MODIFIER=MISSION : Fais un résumé complet. Ne mentionne jamais le mot 'transcription' ou 'document'. Format attendu (Rédigé en %TARGET_LANG%) : - Un résumé exécutif (3-5 lignes) commençant directement par 'La réunion porte sur...' - Les points clés discutés (liste à puces). - Une liste d'actions claires (Qui fait quoi et quand)."
    set "SUFFIX=_Resume"
) else if "%USER_CHOICE%"=="3" (
    set "MODIFIER=MISSION : Organise les échanges dans un tableau Markdown rédigé en %TARGET_LANG% avec les colonnes : [Sujet évoqué | Résumé des échanges | Décisions ou actions requises]."
    set "SUFFIX=_Tableau"
) else if "%USER_CHOICE%"=="4" (
    set "MODIFIER=MISSION : Analyse de manière approfondie en %TARGET_LANG% les enjeux implicites, explique les termes techniques complexes ou résume les débats contradictoires."
    set "SUFFIX=_Analyse"
) else if "%USER_CHOICE%"=="5" (
    set /p "CUSTOM_PROMPT=✍️ Saisissez votre prompt personnalisé : "
    set "MODIFIER=Instruction de l'utilisateur : !CUSTOM_PROMPT!. Réponds obligatoirement en %TARGET_LANG%."
    set "SUFFIX=_Custom"
) else (
    echo ⚠️ Choix invalide. Retour au menu.
    goto :main_loop
)

:: Génération d'un Horodatage unique
set "t=%time: =0%"
set "TIMESTAMP=%date:~-4%%date:~3,2%%date:~0,2%_%t:~0,2%%t:~3,2%%t:~5,2%"
set "OUTPUT_FILE=%DIR_PATH%%FILE_BASE%%SUFFIX%_%TIMESTAMP%.txt"

echo 🚀 Lancement de l'analyse par l'IA locale (%MODEL_NAME%)...
echo ⏳ Opération en cours...

:: Utilisation de PowerShell pour construire proprement le JSON de l'API Ollama (gère les sauts de lignes et guillemets du fichier source)
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$text = Get-Content -Raw -Path '%TRANSCRIPTION_PATH%' -Encoding UTF8;" ^
    "$sysPrompt = '%SYSTEM_PROMPT%';" ^
    "$userPrompt = '%MODIFIER%' + [Environment]::NewLine + [Environment]::NewLine + 'TRANSCRIPTION BRUTE :' + [Environment]::NewLine + $text;" ^
    "$body = @{ model = '%MODEL_NAME%'; messages = @( @{ role = 'system'; content = $sysPrompt }, @{ role = 'user'; content = $userPrompt } ); stream = $false } | ConvertTo-Json -Depth 5;" ^
    "$response = Invoke-RestMethod -Method Post -Uri 'http://localhost:11434/api/chat' -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json; charset=utf-8';" ^
    "$cleanText = $response.message.content -replace '\x1B\[[0-9;]*[a-zA-Z]', '';" ^
    "[System.IO.File]::WriteAllText('%OUTPUT_FILE%', $cleanText, [System.Text.Encoding]::UTF8)"

echo 🎉 Action terminée avec succès !
echo 📄 Fichier propre généré : %OUTPUT_FILE%

goto :main_loop