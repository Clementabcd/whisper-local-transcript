#!/bin/bash

# Quitter immédiatement en cas d'erreur critique
set -e

LOG_FILE="post_process_error.log"

erreur_handler() {
    echo "❌ Une erreur est survenue. Consultez $LOG_FILE." >> /dev/stderr
    echo "[$(date)] Erreur à la ligne $1 dans la commande : '$2'" >> "$LOG_FILE"
    exit 1
}
trap 'erreur_handler $LINENO "$BASH_COMMAND"' ERR

echo "================================================================="
echo "   Assistant de Post-Traitement LLM Local (Correction & Résumé)"
echo "================================================================="

# -----------------------------------------------------------------
# 1. VÉRIFICATION ET CONFIGURATION D'OLLAMA
# -----------------------------------------------------------------
if ! command -v ollama &> /dev/null; then
    echo "🔄 Ollama n'est pas détecté. Installation en cours..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        if ! command -v brew &> /dev/null; then
            echo "❌ Homebrew est requis pour installer Ollama automatiquement." && exit 1
        fi
        brew install ollama >> "$LOG_FILE" 2>&1
        echo "🔄 Démarrage du service Ollama..."
        brew services start ollama >> "$LOG_FILE" 2>&1
        sleep 3
    elif [[ -f /etc/debian_version ]]; then
        curl -fsSL https://ollama.com/install.sh | sh >> "$LOG_FILE" 2>&1
    else
        echo "❌ OS non supporté automatiquement. Installez Ollama : https://ollama.com" && exit 1
    fi
fi

# -----------------------------------------------------------------
# 2. SÉLECTION DU MODÈLE DE LANGAGE
# -----------------------------------------------------------------
echo "🤖 Choisissez le modèle LLM local à utiliser :"
echo "1) Gemma 2 (2B) - ~1.6 Go [Par défaut, ultra-rapide]"
echo "2) Gemma 2 (9B) - ~5.5 Go [Très performant]"
echo "3) Qwen 2.5 (1.5B) - ~980 Mo [Ultra-léger]"
echo "4) Qwen 2.5 (7B) - ~4.7 Go [Excellent en synthèse/tableaux]"
echo "5) Llama 3.1 (8B) - ~4.7 Go [Trilingue et robuste, recommandé pour la langue]"
echo "6) Mistral (7B) - ~4.1 Go [Référence francophone]"
read -p "Votre choix (1-6) [1] : " MODEL_CHOICE

case "$MODEL_CHOICE" in
    2) MODEL_NAME="gemma2:9b" ;;
    3) MODEL_NAME="qwen2.5:1.5b" ;;
    4) MODEL_NAME="qwen2.5:7b" ;;
    5) MODEL_NAME="llama3.1:8b" ;;
    6) MODEL_NAME="mistral:7b" ;;
    *) MODEL_NAME="gemma2:2b" ;;
esac

echo "🔄 Vérification de la présence du modèle ($MODEL_NAME)..."
if ! ollama list | grep -q "$MODEL_NAME"; then
    echo "📥 Téléchargement du modèle $MODEL_NAME (cette étape ne se produit qu'une seule fois)..."
    ollama pull "$MODEL_NAME"
fi

echo "✅ Le modèle $MODEL_NAME est prêt."
echo "-----------------------------------------------------------------"

# -----------------------------------------------------------------
# 3. SÉLECTION DE LA TRANSCRIPTION BRUTE
# -----------------------------------------------------------------
echo "📂 Glissez-déposez votre fichier de transcription (.txt ou .json) ici :"
read -r RAW_INPUT

TRANSCRIPTION_PATH=$(echo "$RAW_INPUT" | sed -e 's/^['\''"]//' -e 's/['\''"]$//' -e 's/\\//g' -e 's/ *$//')

if [ ! -f "$TRANSCRIPTION_PATH" ]; then
    echo "❌ Fichier introuvable : $TRANSCRIPTION_PATH"
    exit 1
fi

TEXT_CONTENT=$(cat "$TRANSCRIPTION_PATH")
DIR_PATH=$(dirname "$TRANSCRIPTION_PATH")
FILE_BASE=$(basename "$TRANSCRIPTION_PATH" .txt)

# -----------------------------------------------------------------
# 4. CHOIX DE LA LANGUE DE SORTIE
# -----------------------------------------------------------------
echo "-----------------------------------------------------------------"
echo "🌐 Dans quelle langue souhaitez-vous obtenir le résultat ?"
read -p "Langue (ex: Français, Anglais, Espagnol...) [Français] : " TARGET_LANG
if [ -z "$TARGET_LANG" ]; then
    TARGET_LANG="Français"
fi

# -----------------------------------------------------------------
# 5. BOUCLE PRINCIPALE D'ACTIONS
# -----------------------------------------------------------------
while true; do
    echo "-----------------------------------------------------------------"
    echo "✨ Quelle action souhaitez-vous effectuer sur cette transcription ?"
    echo "1) 📝 Transcription intégrale fluidifiée (Garder 100% du texte original, corriger fautes/tics)"
    echo "2) 📊 Résumé exécutif complet (Résumé + Points clés + Actions 'Qui fait quoi')"
    echo "3) 🧱 Synthèse sous forme de Tableau structurel"
    echo "4) 🧠 Explication pédagogique / Analyse des points complexes"
    echo "5) ✍️ Prompt personnalisé (Saisissez votre propre consigne)"
    echo "6) ❌ Quitter le script"
    read -p "Votre choix (1-6) : " USER_CHOICE

    if [ "$USER_CHOICE" -eq 6 ] 2>/dev/null; then
        echo "👋 Au revoir !"
        break
    fi

    # Rôle Système ultra-strict séparé du contenu
    SYSTEM_PROMPT="Tu es un secrétaire de direction expert. Tu dois rédiger TOUTES tes réponses uniquement en $TARGET_LANG. Interdiction absolue d'utiliser l'anglais. Tu parles directement du fond de la réunion, sans jamais dire 'la transcription parle de' ou 'ce document montre que'."

    case "$USER_CHOICE" in
        1)
            MODIFIER="MISSION : Agis comme un correcteur d'orthographe et de grammaire textuel. Tu dois réécrire TOUT le texte fourni, mot à mot, du début à la fin. 
- Interdiction absolue de résumer, de condenser ou de couper des paragraphes.
- Nettoie uniquement les tics de langage oraux ('euh', 'du coup', 'en fait', 'voilà') et corrige les fautes de grammaire ou les mots mal compris par l'audio.
- Restitue 100% du texte d'origine nettoyé en $TARGET_LANG."
            SUFFIX="_TexteIntegral"
            ;;
        2)
            MODIFIER="MISSION : Fais un résumé complet. Ne mentionne jamais le mot 'transcription' ou 'document'.
Format attendu (Rédigé en $TARGET_LANG) :
- Un résumé exécutif (3-5 lignes) commençant directement par 'La réunion porte sur...'
- Les points clés discutés (liste à puces).
- Une liste d'actions claires (Qui fait quoi et quand)."
            SUFFIX="_Resume"
            ;;
        3)
            MODIFIER="MISSION : Organise les échanges dans un tableau Markdown rédigé en $TARGET_LANG avec les colonnes : [Sujet évoqué | Résumé des échanges | Décisions ou actions requises]."
            SUFFIX="_Tableau"
            ;;
        4)
            MODIFIER="MISSION : Analyse de manière approfondie en $TARGET_LANG les enjeux implicites, explique les termes techniques complexes ou résume les débats contradictoires."
            SUFFIX="_Analyse"
            ;;
        5)
            echo "✍️ Saisissez votre prompt personnalisé :"
            read -r CUSTOM_PROMPT
            MODIFIER="Instruction de l'utilisateur : $CUSTOM_PROMPT. Réponds obligatoirement en $TARGET_LANG."
            SUFFIX="_Custom"
            ;;
        *)
            echo "⚠️ Choix invalide. Retour au menu."
            continue
            ;;
    esac

    TIMESTAMP=$(date +%H%M%S)
    OUTPUT_FILE="$DIR_PATH/${FILE_BASE}${SUFFIX}_${TIMESTAMP}.txt"

    echo "🚀 Lancement de l'analyse par l'IA locale ($MODEL_NAME)..."
    echo "⏳ Opération en cours..."

    TMP_OUT="${OUTPUT_FILE}.tmp"

    # Construction du JSON structuré pour l'API chat d'Ollama afin de bien séparer le système de la donnée
    # Cela évite que le modèle confonde les instructions et la transcription brute
    JSON_PAYLOAD=$(cat <<EOF
{
  "model": "$MODEL_NAME",
  "messages": [
    {
      "role": "system",
      "content": $(echo "$SYSTEM_PROMPT" | jq -R -s .)
    },
    {
      "role": "user",
      "content": $(echo -e "$MODIFIER\n\nTRANSCRIPTION BRUTE :\n$TEXT_CONTENT" | jq -R -s .)
    }
  ],
  "stream": false
}
EOF
)

    # Envoi de la requête à l'API locale d'Ollama et extraction propre de la réponse brute
    curl -s -X POST http://localhost:11434/api/chat -d "$JSON_PAYLOAD" | jq -r '.message.content' > "$TMP_OUT"

    # Nettoyage des codes d'échappement ANSI
    sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g' "$TMP_OUT" > "$OUTPUT_FILE"
    rm -f "$TMP_OUT"

    echo "🎉 Action terminée avec succès !"
    echo "📄 Fichier propre généré : $OUTPUT_FILE"
done
