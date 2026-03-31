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
    [
      # Message "system" : définit le rôle et le comportement de l'IA
      {
        role: "system",
        content: system_prompt
      },
      # Message "user" : la demande concrète
      {
        role: "user",
        content: user_prompt
      }
    ]
  end

  # Prompt système — définit le personnage que joue l'IA
  def system_prompt
    <<~PROMPT
      Tu es un maître conteur d'histoires épiques pour enfants, dans le style des grands films d'aventure.
      Tu écris en français, avec un style vivant, immersif et plein d'action.

      Règles absolues :
      - Les enfants NE "partent pas à l'aventure" — ils SONT directement les héros dès la première phrase.
        Exemple : "Isaac brandit son sabre de samouraï" (pas "Isaac rêvait d'être samouraï").
      - Chaque scène est cinématographique : on voit, on entend, on ressent.
      - Les dialogues sont percutants et révèlent le caractère des personnages.
      - Le rythme est dynamique : action, tension, rebondissement, résolution.
      - Les caractéristiques physiques des enfants (lunettes, couleur des yeux, etc.) apparaissent dans l'histoire.
      - L'histoire transmet une valeur positive sans jamais être moralisatrice.
      - Pas de violence graphique, mais les combats, défis et dangers sont permis et excitants.
    PROMPT
  end

  # Prompt utilisateur — la demande précise avec tous les paramètres de l'histoire
  def user_prompt
    # Récupération des paramètres de l'histoire
    value_label    = educational_value_label
    level_label    = @story.reading_level == "intermediate" ? "intermédiaire" : "débutant"
    duration_label = "#{@story.duration_minutes} minutes de lecture"

    prompt = <<~PROMPT
      Écris une histoire épique avec ces paramètres :

      ⚔️  Héros principal : #{@child.avatar_description}
      💫 Valeur à transmettre : #{value_label}
      📚 Niveau de lecture : #{level_label}
      ⏱️  Durée : #{duration_label} (environ #{@story.duration_minutes * 200} mots)
    PROMPT

    # Si des enfants supplémentaires sont présents, ils sont CO-HÉROS (pas personnages secondaires)
    extra = @story.extra_children.to_a
    if extra.any?
      descriptions = extra.map { |c| c.avatar_description }.join(" ; ")
      prompt += "\n⚔️  Co-héros (aussi importants que le héros principal) : #{descriptions}"
      prompt += "\n→ Tous les héros apparaissent DÈS LA PREMIÈRE SCÈNE et agissent ensemble."
    end

    # La description libre est le cœur de l'aventure — les enfants sont DIRECTEMENT dans ce rôle
    if @story.custom_theme.present?
      prompt += "\n🌟 L'aventure : #{@story.custom_theme}"
      prompt += "\n→ Les héros SONT déjà dans cette situation dès la première ligne — pas d'introduction."
    end

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
    if @story.interactive?
      nb_choices = interactive_choices_count
      chapters   = nb_choices + 1   # Ex: 3 choix = 4 chapitres

      prompt += <<~INTERACTIVE

        IMPORTANT — Mode interactif (#{nb_choices} choix) :
        L'histoire comporte #{chapters} chapitres.
        #{nb_choices == 1 ? "À la fin du chapitre 2" : "À la fin de chaque chapitre sauf le dernier"}, insère un bloc de choix avec exactement ce format :
        [CHOIX]
        Question : (une question courte et excitante pour l'enfant)
        Option A : (première possibilité d'action)
        Option B : (deuxième possibilité d'action)
        [FIN CHOIX]
        → Ne continue PAS l'histoire après un [FIN CHOIX] — arrête-toi là, la suite sera générée après la décision de l'enfant.
      INTERACTIVE
    end

    prompt
  end

  # Construit les messages pour la continuation après un choix interactif
  def build_continuation_messages(story_choice)
    [
      {
        role: "system",
        content: system_prompt
      },
      {
        role: "user",
        content: user_prompt
      },
      # L'histoire déjà générée (avant le choix)
      {
        role: "assistant",
        content: @story.content
      },
      # Le choix fait par l'enfant
      {
        role: "user",
        content: <<~CHOICE
          L'enfant a choisi : #{story_choice.chosen_text}

          Continue l'histoire à partir de ce choix.
          Écris le 3ème chapitre et la conclusion (environ 200 mots).
          Garde le même style et termine par une belle morale.
        CHOICE
      }
    ]
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
end
