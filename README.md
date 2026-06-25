# 🎙️ Local Transcriber & LLM Assistant

Une suite d'outils légers, performants et **100 % locaux** pour transcrire vos fichiers audio/vidéo et analyser vos transcriptions à l'aide de l'intelligence artificielle. Aucune donnée ne quitte votre ordinateur : tout s'exécute sur votre machine grâce à **Whisper** et **Ollama**.

---

## ✨ Fonctionnalités

### 1. Script de Transcription (`transcribe`)
*   **Drag & Drop :** Glissez-déposez simplement votre fichier audio ou vidéo dans le terminal.
*   **Normalisation Intelligente :** Conversion automatique en MP3 Mono 16kHz optimisé pour la reconnaissance vocale via FFmpeg.
*   **Anti-Saturation RAM/CPU :** Découpage automatique optionnel par tranches de 20 minutes pour les fichiers volumineux.
*   **Affichage en temps réel :** Visualisez la barre de progression de la transcription directement dans votre invite de commande.
*   **Multi-formats :** Exportez vos résultats au format `.txt`, `.srt` (sous-titres), `.vtt` ou `.json`.

### 2. Script d'Analyse & Post-Traitement (`post_process`)
*   **Multi-modèles :** Choisissez dynamiquement la taille et la famille de votre LLM local (Gemma 2, Qwen 2.5, Llama 3.1, Mistral).
*   **Traitement en boucle :** Enchaînez plusieurs analyses à la suite sur le même fichier sans relancer le script.
*   **Gestion multilingue :** Demandez un résultat dans la langue de votre choix (Français, Anglais, Espagnol, etc.).
*   **Cinq modes d'action prédéfinis :**
    1.  *Transcription fluidifiée :* Nettoyage du verbatim (retrait des « euh », tics de langage, corrections orthographiques) sans aucune réécriture ni résumé.
    2.  *Résumé exécutif :* Synthèse de 3 à 5 lignes axée sur le fond de la réunion, points clés et plan d'action (Qui fait quoi et quand).
    3.  *Tableau structurel :* Organisation claire des échanges au format Markdown.
    4.  *Analyse pédagogique :* Explication des termes complexes, des non-dits ou des débats contradictoires.
    5.  *Prompt personnalisé :* Saisissez directement votre propre consigne à l'IA.

---

## 🛠️ Prérequis

Le projet a été pensé pour installer automatiquement ses dépendances lors de la première exécution si elles sont manquantes :

*   **macOS / Linux :** Le script utilise [Homebrew](https://brew.sh/) pour installer `FFmpeg` et `Ollama`.
*   **Windows :** Le script utilise le gestionnaire natif `Winget` pour installer `FFmpeg`, `Python` et `Ollama`.

---

## 🚀 Installation & Utilisation

### 🍏 Sur macOS / Linux

1. Téléchargez les scripts `.sh` dans le dossier de votre choix.
2. Ouvrez votre Terminal et rendez les scripts exécutables :
   ```bash
   chmod +x transcribe.sh post_process.sh

```

3. Lancez l'outil de votre choix :
```bash
./transcribe.sh      # Pour transcrire un fichier audio/vidéo
./post_process.sh    # Pour analyser ou nettoyer un fichier texte

```



### 🪟 Sur Windows

1. Téléchargez les fichiers `.bat` dans le dossier de votre choix.
2. Double-cliquez simplement sur :
* `transcribe.bat` pour lancer la transcription.
* `post_process.bat` pour exécuter l'assistant de résumé/correction.



> 💡 **Note pour le premier lancement :** Si le script installe des composants système pour la première fois (comme Python ou FFmpeg), il vous sera demandé de fermer et de rouvrir votre terminal pour que Windows prenne en compte les nouvelles variables d'environnement.

---

## 🤖 Modèles recommandés

Pour le script de post-traitement, les modèles suivants sont intégrés dans le menu de sélection :

* **Gemma 2 (2B) - ~1.6 Go :** Idéal pour les configurations légères, ultra-rapide.
* **Llama 3.1 (8B) - ~4.7 Go :** Recommandé pour une excellente tenue de la langue et le respect strict des consignes systémiques.
* **Mistral (7B) - ~4.1 Go :** La référence pour une analyse fine et naturelle de la langue française.

---

## 📁 Structure des fichiers générés

Vos fichiers de sortie sont enregistrés proprement **dans le même dossier** que votre fichier audio ou texte d'origine.

* `[Nom]_Transcription.txt` (Transcription brute)
* `[Nom]_TexteIntegral_[Heure].txt` (Version fluidifiée sans tics de langage)
* `[Nom]_Resume_[Heure].txt` (Résumé exécutif et plan d'action)

En cas d'anomalie, un fichier `error.log` ou `post_process_error.log` est généré localement pour diagnostiquer le problème sans polluer votre affichage principal.

---

## 📝 Licence

Ce projet est sous licence MIT. Libre à vous de le modifier et de le partager !
