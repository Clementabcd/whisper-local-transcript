#!/bin/bash

# Configuration pour quitter le script immédiatement en cas d'erreur critique
set -e

LOG_FILE="error.log"

# Fonction de gestion des erreurs (écrit dans le log uniquement en cas de plantage)
erreur_handler() {
    echo "❌ Une erreur est survenue lors de l'exécution. Consultez $LOG_FILE pour plus de détails." >> /dev/stderr
    echo "[$(date)] Erreur à la ligne $1 dans la commande : '$2'" >> "$LOG_FILE"
    exit 1
}
trap 'erreur_handler $LINENO "$BASH_COMMAND"' ERR

echo "================================================================="
echo "   Assistant de Transcription Audio Universel (Whisper AI)"
echo "================================================================="

# -----------------------------------------------------------------
# 1. DÉTECTION DE L'OS ET DES ARCHITECTURES
# -----------------------------------------------------------------
OS_TYPE="unknown"
ARCH_TYPE=$(uname -m)

if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macOS"
elif [[ -f /etc/debian_version ]]; then
    OS_TYPE="Debian/Ubuntu"
fi

echo "💻 Système détecté : $OS_TYPE ($ARCH_TYPE)"

# -----------------------------------------------------------------
# 2. VÉRIFICATION ET INSTALLATION DES DÉPENDANCES
# -----------------------------------------------------------------
echo "🔍 Vérification des prérequis..."

# FFmpeg
if ! command -v ffmpeg &> /dev/null; then
    echo "🔄 FFmpeg manquant. Installation en cours..."
    if [ "$OS_TYPE" == "macOS" ]; then
        if ! command -v brew &> /dev/null; then
            echo "❌ Homebrew requis sur Mac. Installez-le (https://brew.sh) et relancez." && exit 1
        fi
        brew install ffmpeg >> "$LOG_FILE" 2>&1
    elif [ "$OS_TYPE" == "Debian/Ubuntu" ]; then
        sudo apt update && sudo apt install -y ffmpeg >> "$LOG_FILE" 2>&1
    else
        echo "❌ OS non supporté automatiquement pour FFmpeg. Installez-le manuellement." && exit 1
    fi
fi

# Python 3
if ! command -v python3 &> /dev/null; then
    echo "🔄 Python3 manquant. Installation en cours..."
    if [ "$OS_TYPE" == "macOS" ]; then
        brew install python >> "$LOG_FILE" 2>&1
    elif [ "$OS_TYPE" == "Debian/Ubuntu" ]; then
        sudo apt update && sudo apt install -y python3 python3-pip python3-venv >> "$LOG_FILE" 2>&1
    fi
fi

# Configuration PIP
PIP_CMD="pip3"
if ! command -v pip3 &> /dev/null; then PIP_CMD="pip"; fi

# OpenAI Whisper
if ! python3 -c "import whisper" &> /dev/null; then
    echo "🔄 Installation de OpenAI Whisper..."
    $PIP_CMD install -U openai-whisper >> "$LOG_FILE" 2>&1
fi

# Booster Apple Silicon automatique (M1/M2/M3/M4)
if [ "$OS_TYPE" == "macOS" ] && [ "$ARCH_TYPE" == "arm64" ]; then
    if ! python3 -c "import torch; print(torch.backends.mps.is_available())" 2>/dev/null | grep -q "True"; then
        echo "🚀 Activation de l'accélération matérielle Apple Silicon..."
        $PIP_CMD install --pre torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/nightly/cpu >> "$LOG_FILE" 2>&1
    fi
fi

echo "✅ Toutes les dépendances sont prêtes."
echo "-----------------------------------------------------------------"

# -----------------------------------------------------------------
# 3. INTERACTION UTILISATEUR (Drag & Drop + Options)
# -----------------------------------------------------------------
# Demande du fichier avec Drag & Drop
echo "📂 Glissez-déposez votre fichier audio ou vidéo ici, puis appuyez sur Entrée :"
read -r RAW_INPUT

# Nettoyage des guillemets et espaces du Drag & Drop
CLEANED_PATH=$(echo "$RAW_INPUT" | sed -e 's/^['\''"]//' -e 's/['\''"]$//' -e 's/\\//g' -e 's/ *$//')

if [ ! -f "$CLEANED_PATH" ]; then
    echo "❌ Le fichier spécifié n'existe pas : $CLEANED_PATH"
    exit 1
fi

# Extraction des informations de chemin
AUDIO_DIR=$(dirname "$CLEANED_PATH")
FILE_NAME=$(basename "$CLEANED_PATH")
FILE_BASE="${FILE_NAME%.*}"

# Sélection du modèle
echo "🤖 Choisissez le modèle Whisper (recommandé : turbo ou medium) :"
echo "1) base"
echo "2) small"
echo "3) medium"
echo "4) large-v3-turbo"
read -p "Votre choix (1-4) [4] : " MODEL_CHOICE
case "$MODEL_CHOICE" in
    1) MODEL="base" ;;
    2) MODEL="small" ;;
    3) MODEL="medium" ;;
    *) MODEL="turbo" ;; # Turbo par défaut
esac

# Sélection du format d'exportation
echo "📄 Quel format de transcription souhaitez-vous ?"
echo "1) txt (Texte brut dynamique)"
echo "2) srt (Sous-titres vidéo)"
echo "3) json (Données structurées)"
echo "4) vtt"
read -p "Votre choix (1-4) [1] : " FORMAT_CHOICE
case "$FORMAT_CHOICE" in
    2) EXPORT_FORMAT="srt" ;;
    3) EXPORT_FORMAT="json" ;;
    4) EXPORT_FORMAT="vtt" ;;
    *) EXPORT_FORMAT="txt" ;;
esac

# -----------------------------------------------------------------
# 4. PRÉ-TRAITEMENT AUDIO (Normalisation & Conversion)
# -----------------------------------------------------------------
cd "$AUDIO_DIR"

PROCESSED_AUDIO="${FILE_BASE}_normalized.mp3"
echo "🎵 Optimisation de l'audio (Conversion en MP3 Mono 16kHz + Normalisation)..."
ffmpeg -y -i "$FILE_NAME" -af "loudnorm=I=-16:TP=-1.5:LRA=11" -ac 1 -ar 16000 "$PROCESSED_AUDIO" >> "$LOG_FILE" 2>&1

# Détection de la durée pour fragmentation optionnelle (en secondes)
DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$PROCESSED_AUDIO" | cut -d. -f1)

DECOUPAGE=false
if [ "$DURATION" -gt 1200 ]; then
    DISPLAY_MINS=$((DURATION / 60))
    echo "⏳ Cet audio dure plus de 20 minutes ($DISPLAY_MINS mins)."
    read -p "Voulez-vous le fragmenter par tranches de 20 min pour sécuriser la RAM et le processeur ? (o/n) [o] : " CHOICE
    if [[ "$CHOICE" =~ ^[Nn]$ ]]; then
        DECOUPAGE=false
    else
        DECOUPAGE=true
    fi
fi

# -----------------------------------------------------------------
# 5. MOTEUR DE TRANSCRIPTION (AVEC OU SANS FRAGMENTATION)
# -----------------------------------------------------------------
FINAL_OUTPUT="${FILE_BASE}_Transcription.${EXPORT_FORMAT}"

if [ "$DECOUPAGE" = true ]; then
    echo "✂️ Découpage de l'audio en segments de 20 minutes..."
    TMP_DIR="tmp_chunks_$(date +%s)"
    mkdir -p "$TMP_DIR"
    
    ffmpeg -i "$PROCESSED_AUDIO" -f segment -segment_time 1200 -c copy "$TMP_DIR/chunk_%03d.mp3" >> "$LOG_FILE" 2>&1
    
    echo "🚀 Transcription séquentielle des segments..."
    cd "$TMP_DIR"
    
    for chunk in chunk_*.mp3; do
        echo "--------------------------------------------------"
        echo "   -> Traitement actif de : $chunk"
        echo "--------------------------------------------------"
        # Suppression de la redirection pour afficher la progression de Whisper en direct !
        whisper "$chunk" --model "$MODEL" --language French --output_format "$EXPORT_FORMAT"
    done
    
    echo "--------------------------------------------------"
    echo "🔗 Fusion et nettoyage des fichiers générés..."
    cd ..
    
    # Recollage des fichiers
    cat "$TMP_DIR"/chunk_*."${EXPORT_FORMAT}" > "$FINAL_OUTPUT"
    
    # Nettoyage des fichiers temporaires
    rm -rf "$TMP_DIR"
else
    echo "🚀 Lancement de la transcription globale (Fichier unique)..."
    whisper "$PROCESSED_AUDIO" --model "$MODEL" --language French --output_format "$EXPORT_FORMAT"
    mv "${FILE_BASE}_normalized.${EXPORT_FORMAT}" "$FINAL_OUTPUT"
fi

# Nettoyage de l'audio normalisé intermédiaire
rm -f "$PROCESSED_AUDIO"

echo "================================================================="
echo "🎉 Opération terminée avec succès !"
echo "📄 Votre transcription est prête ici : $AUDIO_DIR/$FINAL_OUTPUT"
echo "================================================================="
