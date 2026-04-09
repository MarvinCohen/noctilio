class StoryGeneratorService
  # ============================================================
  # Service de génération d'histoires via Groq (Llama 3.3)
  # ============================================================
  # Responsabilité unique : prendre une Story en base de données
  # et générer son contenu via l'API Groq.
  #
  # Groq est un service gratuit qui expose une API compatible OpenAI.
  # On utilise donc le gem ruby-openai en pointant vers l'endpoint Groq.
  #
  # Utilisation :
  #   service = StoryGeneratorService.new(story)
  #   result = service.call
  #   # result = { success: true, content: "Il était une fois..." }

  # Modèle Groq utilisé pour la génération de texte
  # llama-3.3-70b-versatile : modèle Llama 3.3 70B, excellent pour les histoires
  # Gratuit sur Groq (rate limit généreux pour le développement)
  MODEL = "llama-3.3-70b-versatile"

  # URL de base de l'API Groq — compatible avec le format OpenAI
  # Le gem ruby-openai accepte un uri_base custom pour pointer vers d'autres fournisseurs
  GROQ_API_BASE = "https://api.groq.com/openai/v1"

  def initialize(story)
    # On stocke l'histoire pour y accéder dans toutes les méthodes
    @story = story

    # On récupère l'enfant pour personnaliser l'histoire
    @child = story.child

    # Initialisation du client avec l'API Groq
    # uri_base : redirige les appels vers Groq au lieu d'OpenAI
    # access_token : clé API Groq stockée dans .env (GROQ_API_KEY)
    @client = OpenAI::Client.new(
      access_token: ENV.fetch("GROQ_API_KEY"),
      uri_base: GROQ_API_BASE
    )
  end

  # Génère l'histoire complète et retourne le contenu texte
  # Retourne un hash : { success: true/false, content: "...", error: "..." }
  def call
    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: build_messages,
        temperature: 0.85,   # Haute créativité pour les histoires
        max_tokens: tokens_for_duration,
        top_p: 0.9           # Diversité dans le choix des mots
      }
    )

    content = response.dig("choices", 0, "message", "content")

    if content.present?
      { success: true, content: content }
    else
      { success: false, error: "La réponse de l'IA était vide" }
    end
  rescue OpenAI::Error => e
    # En cas d'erreur côté OpenAI (quota, timeout, etc.)
    { success: false, error: "Erreur OpenAI : #{e.message}" }
  rescue StandardError => e
    { success: false, error: "Erreur inattendue : #{e.message}" }
  end

  # Génère la "timeline alternative" — ce qui se serait passé avec l'autre option
  # L'enfant a choisi A → on génère ce qui aurait donné B, et inversement
  # La logique est identique à continue_with_choice mais on inverse le chosen_option
  def generate_alternative(story_choice)
    # Crée un objet temporaire (non persisté) avec l'option inverse
    # Évite de modifier le vrai choix en base — c'est juste pour le prompt
    alternative_choice = story_choice.dup
    alternative_choice.chosen_option = story_choice.chosen_option == "a" ? "b" : "a"

    # Appelle le même moteur de continuation avec l'option inversée
    response = @client.chat(
      parameters: {
        model:       MODEL,
        messages:    build_continuation_messages(alternative_choice),
        temperature: 0.85,
        max_tokens:  600,
        top_p:       0.9
      }
    )

    content = response.dig("choices", 0, "message", "content")

    if content.present?
      { success: true, content: content }
    else
      { success: false, error: "La timeline alternative était vide" }
    end
  rescue OpenAI::Error => e
    { success: false, error: "Erreur OpenAI : #{e.message}" }
  rescue StandardError => e
    { success: false, error: "Erreur inattendue : #{e.message}" }
  end

  # Génère la suite de l'histoire après qu'un choix a été fait
  # Appelée pour le mode interactif quand l'enfant choisit une option
  def continue_with_choice(story_choice)
    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: build_continuation_messages(story_choice),
        temperature: 0.85,
        max_tokens: 600,   # Suite plus courte — environ 3 paragraphes
        top_p: 0.9
      }
    )

    content = response.dig("choices", 0, "message", "content")

    if content.present?
      { success: true, content: content }
    else
      { success: false, error: "La continuation était vide" }
    end
  rescue OpenAI::Error => e
    { success: false, error: "Erreur OpenAI : #{e.message}" }
  end

  private

  # Construit les messages envoyés à l'API OpenAI
  # Format requis par l'API : tableau de { role:, content: }
  def build_messages
    messages = [
      # Message "system" : définit le rôle et le comportement de l'IA
      { role: "system", content: system_prompt },
      # Message "user" : la demande concrète
      { role: "user", content: user_prompt }
    ]

    # Si c'est un épisode de suite, on injecte le contexte de l'histoire parente
    # pour que l'IA assure la continuité narrative (mêmes personnages, même univers, même ton)
    if @story.sequel? && @story.parent_story.present?
      messages << { role: "user", content: parent_context_prompt }
    end

    messages
  end

  # Prompt système — personnage et règles NON-NÉGOCIABLES de l'IA
  # IMPORTANT : les directives critiques sont EN PREMIER (Llama pèse plus les premiers tokens)
  def system_prompt
    <<~PROMPT
      Tu es le meilleur conteur d'histoires épiques et magiques pour enfants au monde.
      Tu écris en français, dans le style des grands films d'animation (Pixar, Miyazaki, Disney).

      RÈGLES NON-NÉGOCIABLES — respecte-les à la lettre :

      1. INCIPIT EN ACTION : La première phrase plonge IMMÉDIATEMENT dans l'action.
         Les héros SONT déjà le personnage demandé — ils ne "rêvent" pas de l'être.
         ✓ "La lame d'Isaac fendit l'air d'un éclair argenté."
         ✗ "Isaac rêvait de devenir samouraï."

      2. STYLE CINÉMATOGRAPHIQUE : Chaque scène est visuelle, sensorielle, immersive.
         Utilise les 5 sens. Décris les lumières, les textures, les sons, les odeurs.
         Les dialogues révèlent le caractère — ils sont percutants, jamais plats.

      3. STRUCTURE NARRATIVE PARFAITE :
         - Acte 1 (20%) : situation de départ, héros en action, enjeu clair
         - Acte 2 (60%) : montée de tension, obstacles, retournements, alliance
         - Acte 3 (20%) : climax intense, résolution satisfaisante, leçon subtile

      4. CARACTÉRISTIQUES PHYSIQUES : Intègre naturellement les détails physiques
         des héros (lunettes, couleur des cheveux, des yeux, etc.) dans les scènes.

      5. VALEUR ÉDUCATIVE SUBTILE : La leçon morale se vit dans l'histoire —
         jamais expliquée, jamais moralisatrice. L'enfant la ressent, pas la subit.

      6. VOCABULAIRE ADAPTÉ : Adapté à l'âge, mais jamais simplet.
         Les enfants aiment les grands mots quand le contexte les rend compréhensibles.
    PROMPT
  end

  # Prompt utilisateur — la demande précise avec tous les paramètres de l'histoire
  def user_prompt
    # Récupération des paramètres de l'histoire
    value_label    = educational_value_label
    duration_label = "#{@story.duration_minutes} minutes de lecture"

    # Construction du prompt utilisateur — variables enfant + contexte de l'aventure
    # Chain of Thought : on guide le modèle étape par étape pour une meilleure cohérence
    extra        = @story.extra_children.to_a
    all_heroes   = [@child] + extra
    heroes_desc  = all_heroes.map { |c| "• #{c.avatar_description}" }.join("\n")
    word_count   = @story.duration_minutes * 200

    prompt = <<~PROMPT
      PARAMÈTRES DE L'HISTOIRE :

      ⚔️  HÉROS (présents ensemble dès la première phrase) :
      #{heroes_desc}

      🌟 AVENTURE : #{@story.custom_theme.presence || "une aventure épique et magique"}
      💫 VALEUR À TRANSMETTRE : #{value_label}
      ⏱️  LONGUEUR OBLIGATOIRE : #{word_count} mots minimum — ne termine PAS avant d'avoir atteint #{word_count} mots.

      AVANT D'ÉCRIRE, pense étape par étape (ne pas afficher cette réflexion) :
      1. Comment les héros SONT-ILS déjà dans la situation dès la 1ère phrase ?
      2. Quel est l'obstacle principal et comment la valeur "#{value_label}" aide à le surmonter ?
      3. Quel moment visuel fort peut ouvrir et clore l'histoire ?

      MAINTENANT ÉCRIS L'HISTOIRE :
      — Titre accrocheur sur la première ligne (sans "Titre :" ni "#")
      — #{chapter_count} chapitres avec titres courts et percutants — chaque chapitre fait au moins #{word_count / chapter_count} mots
      — Première phrase = action immédiate, héros déjà dans leur rôle
      — Chaque chapitre se termine sur une tension ou une découverte
      — Finale mémorable avec leçon vécue, pas expliquée
    PROMPT

    # Instructions de format
    prompt += <<~FORMAT

      Format de l'histoire :
      - Commence par un titre accrocheur sur la première ligne (sans "Titre :")
      - Divise l'histoire en 3 chapitres courts avec des titres
      - Utilise des dialogues et des descriptions visuelles
      - Termine par une belle morale ou leçon douce
    FORMAT

    # Mode interactif : nombre de choix selon la durée de l'histoire
    # 5 min → 1 choix, 10 min → 2 choix, 15 min → 3 choix
    # IMPORTANT : tous les blocs [CHOIX] sont dans la génération initiale —
    # la suite après chaque choix sera générée séparément par GenerateStoryContinuationJob
    if @story.interactive?
      nb_choices = interactive_choices_count

      prompt += <<~INTERACTIVE

        IMPORTANT — Mode interactif : insère EXACTEMENT #{nb_choices} bloc(s) de choix.

        RÈGLE ABSOLUE : le bloc [CHOIX] doit apparaître au MOMENT DE TENSION MAXIMALE —
        AVANT que la situation soit résolue, AVANT que le héros agisse, AVANT le dénouement.
        L'histoire doit s'arrêter net sur un dilemme, comme au bord d'un précipice.

        ✓ BON : "Le robot ennemi se dressa face à Isaac. Deux options s'offrirent à lui..."
            → [CHOIX] ← l'enfant décide MAINTENANT
        ✗ MAUVAIS : "Isaac vainquit le robot et rentra chez lui triomphant."
            → [CHOIX] ← trop tard, l'histoire est déjà finie

        Format de chaque bloc (respecte exactement ce format) :
        [CHOIX]
        Question : (question courte au moment de la décision — "Que va faire [héros] ?")
        Option A : (première action possible)
        Option B : (deuxième action possible)
        [FIN CHOIX]

        Après chaque bloc [CHOIX], NE PAS résoudre l'action — arrête-toi là.
        La suite sera générée par l'enfant en faisant son choix.
        Nombre de blocs [CHOIX] : #{nb_choices}, placés avant chaque résolution de chapitre.
      INTERACTIVE
    end

    prompt
  end

  # Construit les messages pour la continuation après un choix interactif
  # N'envoie PAS l'histoire depuis le début — seulement le contexte récent
  # pour que l'IA continue naturellement sans repartir à zéro
  def build_continuation_messages(story_choice)
    # Vérifie s'il reste des choix non résolus après celui-ci (step_number supérieur)
    remaining_choices = @story.story_choices
                              .where(chosen_option: nil)
                              .where("step_number > ?", story_choice.step_number)
                              .count

    # Calcule combien de mots pour cette continuation
    continuation_words = tokens_for_duration / 4   # ~quart de l'histoire par continuation

    # Prend les 1500 derniers caractères de l'histoire — assez pour la cohérence narrative,
    # sans envoyer tout le texte depuis le début (qui ferait repartir l'IA au début)
    recent_context = @story.content.to_s.last(1500)

    if remaining_choices > 0
      # Il reste des choix à venir — génère un passage intermédiaire qui fait avancer l'histoire
      # sans la conclure (l'enfant aura encore un choix à faire après)
      continuation_instruction = <<~CHOICE
        L'histoire s'intitule "#{@story.title}".

        Voici la fin du dernier passage :
        #{recent_context}

        L'enfant a choisi : #{story_choice.chosen_text}

        Continue DIRECTEMENT depuis ce choix (environ #{continuation_words} mots).
        Ne résume pas ce qui s'est passé avant — plonge immédiatement dans l'action.
        Même style cinématographique, même ton.
        NE termine PAS l'histoire — l'aventure n'est pas encore finie, d'autres rebondissements attendent.
        Arrête-toi sur un moment de tension ou de découverte.
      CHOICE
    else
      # Dernier choix — génère la conclusion finale de l'histoire
      continuation_instruction = <<~CHOICE
        L'histoire s'intitule "#{@story.title}".

        Voici la fin du dernier passage :
        #{recent_context}

        L'enfant a choisi : #{story_choice.chosen_text}

        C'est le dernier chapitre — écris une conclusion épique et mémorable (environ #{continuation_words} mots).
        Continue DIRECTEMENT depuis ce choix sans résumer ce qui s'est passé avant.
        Le climax doit être intense, la résolution satisfaisante.
        Termine par une leçon vécue naturellement dans l'action — jamais expliquée, jamais moralisatrice.
      CHOICE
    end

    [
      # Le prompt système garde les règles de style (Pixar, structure narrative, etc.)
      { role: "system", content: system_prompt },
      # Un seul message utilisateur avec le contexte récent + le choix + l'instruction
      # Pas de user_prompt original (qui demandait de créer une histoire depuis le début)
      # Pas du contenu complet de l'histoire (qui ferait repartir l'IA au début)
      { role: "user", content: continuation_instruction }
    ]
  end

  # Construit le prompt de contexte pour un épisode de suite
  # Envoie la fin de l'histoire précédente (1500 derniers caractères)
  # pour que l'IA enchaîne naturellement sans répéter ce qui s'est passé
  def parent_context_prompt
    parent = @story.parent_story
    episode_num = @story.episode_number

    # On prend les 1500 derniers caractères — assez pour la cohérence narrative
    # sans surcharger le contexte avec toute l'histoire du début
    recent_context = parent.content.to_s.last(1500)

    <<~PROMPT
      IMPORTANT — C'est l'épisode #{episode_num} d'une saga.

      Cette histoire est la SUITE DIRECTE de "#{parent.title}" (épisode #{episode_num - 1}).

      Voici la fin de l'épisode précédent :
      ---
      #{recent_context}
      ---

      RÈGLES POUR LA SUITE :
      1. Les personnages sont les MÊMES — ne les réintroduis pas comme des inconnus.
      2. Les descriptions physiques des personnages doivent être IDENTIQUES à l'épisode précédent :
         mêmes couleurs de cheveux, yeux, vêtements emblématiques, accessoires caractéristiques.
         L'enfant qui lit doit reconnaître immédiatement ses héros.
      3. Commence immédiatement APRÈS les événements de l'épisode précédent.
      4. Fais référence à au moins UN élément de l'épisode précédent (un lieu, un objet, une décision) pour créer la continuité.
      5. L'enjeu doit être NOUVEAU — une nouvelle aventure, pas une répétition.
      6. Le titre doit indiquer que c'est l'épisode #{episode_num} (ex: "Titre — Épisode #{episode_num}").
    PROMPT
  end

  # Retourne le libellé français de la valeur éducative
  def educational_value_label
    {
      "courage"    => "le courage",
      "sharing"    => "le partage",
      "kindness"   => "la gentillesse",
      "confidence" => "la confiance en soi"
    }.fetch(@story.educational_value.to_s, "les valeurs positives")
  end

  # Calcule le nombre de tokens selon la durée souhaitée
  # 200 mots/min × durée × ~1.5 tokens/mot (français) + marge titres/choix
  # Pas de plafond arbitraire — Groq supporte jusqu'à 8000 tokens
  def tokens_for_duration
    { 5 => 2000, 10 => 3500, 15 => 5500 }.fetch(@story.duration_minutes.to_i, 2000)
  end

  # Retourne le nombre de choix interactifs selon la durée
  # 5 min → 1 choix, 10 min → 2 choix, 15 min → 3 choix
  def interactive_choices_count
    { 5 => 1, 10 => 2, 15 => 3 }.fetch(@story.duration_minutes.to_i, 1)
  end

  # Retourne le nombre de chapitres à générer selon le mode et la durée
  #
  # Non-interactif : toujours 3 chapitres (début / milieu / fin classique)
  #
  # Interactif : un chapitre par choix + 1
  #   5 min  → 1 choix → 2 chapitres (le 2ème se termine sur le choix)
  #   10 min → 2 choix → 3 chapitres
  #   15 min → 3 choix → 4 chapitres
  #
  # Les continuations après chaque choix s'ajoutent ensuite séparément,
  # donc le total lu par l'enfant est bien proportionnel à la durée choisie.
  def chapter_count
    if @story.interactive?
      interactive_choices_count + 1
    else
      3
    end
  end
end
