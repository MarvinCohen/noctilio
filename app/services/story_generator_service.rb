class StoryGeneratorService
  # ============================================================
  # Service de génération d'histoires via OpenAI GPT
  # ============================================================
  # Responsabilité unique : prendre une Story en base de données
  # et générer son contenu via l'API OpenAI.
  #
  # Utilisation :
  #   service = StoryGeneratorService.new(story)
  #   result = service.call
  #   # result = { success: true, content: "Il était une fois..." }

  # Modèle OpenAI utilisé pour la génération de texte
  # GPT-5.2 est le modèle le plus récent et le plus performant (2026)
  MODEL = "gpt-4o"

  def initialize(story)
    # On stocke l'histoire pour y accéder dans toutes les méthodes
    @story = story

    # On récupère l'enfant pour personnaliser l'histoire
    @child = story.child

    # Initialisation du client OpenAI avec la clé API stockée dans .env
    @client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
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
      Tu es un conteur d'histoires pour enfants, expert en récits magiques, éducatifs et adaptés à l'âge.
      Tu écris des histoires en français, avec un vocabulaire adapté à l'enfant.
      Tes histoires sont captivantes, bienveillantes et transmettent toujours une valeur positive.
      Tu utilises des descriptions colorées et des dialogues pour rendre l'histoire vivante.
      Tu n'utilises jamais de violence, de peur intense ou de contenu inapproprié.
    PROMPT
  end

  # Prompt utilisateur — la demande précise avec tous les paramètres de l'histoire
  def user_prompt
    # Récupération des paramètres de l'histoire
    world_label    = @story.world_label
    value_label    = educational_value_label
    level_label    = @story.reading_level == "intermediate" ? "intermédiaire" : "débutant"
    duration_label = "#{@story.duration_minutes} minutes de lecture"

    prompt = <<~PROMPT
      Écris une histoire pour un enfant avec ces paramètres :

      👤 Personnage principal : #{@child.avatar_description}
      🌍 Univers : #{world_label}
      💫 Valeur à transmettre : #{value_label}
      📚 Niveau de lecture : #{level_label}
      ⏱️  Durée : #{duration_label} (environ #{@story.duration_minutes * 200} mots)
    PROMPT

    # Ajoute le thème personnalisé si défini par le parent
    if @story.custom_theme.present?
      prompt += "\n🎯 Thème supplémentaire souhaité par le parent : #{@story.custom_theme}"
    end

    # Instructions de format
    prompt += <<~FORMAT

      Format de l'histoire :
      - Commence par un titre accrocheur sur la première ligne (sans "Titre :")
      - Divise l'histoire en 3 chapitres courts avec des titres
      - Utilise des dialogues et des descriptions visuelles
      - Termine par une belle morale ou leçon douce
    FORMAT

    # Mode interactif : demande de préparer un choix
    if @story.interactive?
      prompt += <<~INTERACTIVE

        IMPORTANT — Mode interactif :
        À la fin du 2ème chapitre, insère exactement ce format :
        [CHOIX]
        Question : (une question courte et claire pour l'enfant)
        Option A : (première possibilité)
        Option B : (deuxième possibilité)
        [FIN CHOIX]
        Ne continue PAS l'histoire après le choix — la suite sera générée après la décision.
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
  # Règle approximative : 200 mots × durée + marge pour les titres
  def tokens_for_duration
    base = @story.duration_minutes.to_i * 300
    [base, 3000].min   # Maximum 3000 tokens par histoire
  end
end
