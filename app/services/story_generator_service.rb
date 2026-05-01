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

  # Génère le prompt image COMPLET via Groq — délègue toute la logique à l'IA
  # Groq connaît l'histoire ET l'apparence physique des héros → il gère tous les cas :
  # pilote de robot, cavalier, héros direct, groupe, etc.
  # Retourne un prompt en anglais (80-120 mots) prêt à envoyer à FLUX/DALL-E
  def generate_image_scene_prompt
    # Construit la description physique de chaque héros pour l'injecter dans le prompt
    heroes_physical = @story.all_children.map do |child|
      parts = ["#{child.name}, #{child.age} year old #{child.gender == 'boy' ? 'boy' : 'girl'}"]
      parts << "blonde hair"              if child.hair_color&.match?(/blond/i)
      parts << "#{child.hair_color} hair" if child.hair_color.present? && !child.hair_color.match?(/blond/i)
      parts << "green eyes"               if child.eye_color&.match?(/vert/i)
      parts << "#{child.eye_color} eyes"  if child.eye_color.present? && !child.eye_color.match?(/vert/i)
      if child.skin_tone.present?
        parts << case child.skin_tone.downcase
                 when /éb[eè]ne|noir|très.?foncé/ then "very dark black ebony skin"
                 when /foncé|brun/                then "dark brown skin"
                 when /métis|caramel|doré/        then "warm golden brown skin"
                 when /olive|mat/                 then "olive skin"
                 when /clair|blanc/               then "fair light skin"
                 else "#{child.skin_tone} skin"
                 end
      end
      parts << child.child_description if child.child_description.present?
      parts.join(", ")
    end.join(" | ")

    # Détecte si un héros a la peau foncée — utilisé comme signal de fallback
    # pour garantir une bonne représentation quand aucun style n'est choisi
    has_dark_skin = @story.all_children.any? { |c| c.skin_tone&.match?(/éb[eè]ne|noir|très.?foncé|brun/i) }

    # Sélectionne le style visuel pour le prompt image :
    #   1. Si l'utilisateur a choisi un style → on l'applique (en tenant compte de la peau si Comics)
    #   2. Sinon → fallback automatique selon la couleur de peau du héros
    style_ref = case @story.image_style
                when "ghibli"
                  "Makoto Shinkai and Studio Ghibli cinematic animation style, soft watercolor pastels, dreamy atmosphere"
                when "comics"
                  # Comics + peau foncée → Spider-Verse est la référence la plus représentative
                  has_dark_skin \
                    ? "Spider-Man Into the Spider-Verse animation style, bold outlines, vibrant saturated colors, Black protagonist" \
                    : "Marvel Comics and Spider-Man Into the Spider-Verse animation style, bold outlines, vibrant saturated colors"
                when "pixar"
                  "Pixar and Disney 3D animation style, warm cinematic lighting, highly detailed CGI, expressive characters"
                when "watercolor"
                  "vintage children's book illustration style, soft watercolor textures, warm hand-painted look, storybook fairy tale"
                else
                  # Fallback automatique : Spider-Verse pour peau foncée, Ghibli sinon
                  has_dark_skin \
                    ? "Spider-Man Into the Spider-Verse and modern Disney animation style, Black protagonist" \
                    : "Makoto Shinkai and Studio Ghibli cinematic animation style"
                end

    response = @client.chat(
      parameters: {
        model:       MODEL,
        messages:    [
          {
            role:    "system",
            content: <<~SYSTEM
              You are an expert at writing image generation prompts for FLUX and DALL-E.
              Your prompts are vivid, specific, and always produce dramatic action scenes.
              You always write in English. You STRICTLY respect character physical descriptions.
              Output ONLY the prompt text, no explanation, no preamble.
            SYSTEM
          },
          {
            role:    "user",
            content: <<~PROMPT
              Write a COMPLETE image generation prompt for the most DRAMATIC and ACTION-PACKED scene of this story.

              HERO PHYSICAL DESCRIPTION (MANDATORY — never change these):
              #{heroes_physical}

              STORY (read to find the most epic visual moment):
              ---
              #{@story.content.to_s.first(3000)}
              ---

              RULES:
              1. Pick the single most visually explosive moment (climax, battle, chase, storm...)
              2. If the hero PILOTS something (robot, spaceship, dragon...): show the vehicle/robot in EPIC BATTLE in the foreground, hero's face visible through cockpit — DO NOT show the child standing next to the robot
              3. If the hero acts directly: show them in full dynamic action
              4. STRICTLY include the exact physical traits: skin color, hair, eyes, accessories
              5. Style: #{style_ref}, highly detailed, cinematic widescreen, dramatic lighting, motion blur, child-safe, no blood
              6. End with: "vibrant colors, dramatic rim lighting, motion blur, cinematic composition"

              Write 80-120 words. ONLY the prompt, nothing else.
            PROMPT
          }
        ],
        temperature: 0.4,  # Basse température — on veut de la précision, pas de créativité
        max_tokens:  200
      }
    )

    response.dig("choices", 0, "message", "content")&.strip
  rescue StandardError => e
    Rails.logger.warn("StoryGeneratorService — échec generate_image_scene_prompt : #{e.message}")
    nil  # En cas d'échec, ImageGeneratorService utilisera le fallback existant
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

      4. CARACTÉRISTIQUES PHYSIQUES : Ne décris JAMAIS un héros comme une fiche
         d'identité ("Léo, un garçon de 7 ans aux cheveux blonds et aux yeux verts").
         Glisse les détails physiques UN PAR UN, au fil de l'action, quand c'est
         pertinent et naturel :
         ✓ "Sa tignasse rousse disparut dans la fumée."
         ✓ "Ses lunettes rondes captèrent un reflet de lumière."
         ✗ "Léo, un garçon de 7 ans aux cheveux roux et aux yeux verts."
         La couleur des yeux en particulier est rarement nécessaire — ne la mentionne
         que si la scène l'exige vraiment (ex: regard intense face à un adversaire).

      5. VALEUR ÉDUCATIVE SUBTILE : La leçon morale se vit dans l'histoire —
         jamais expliquée, jamais moralisatrice. L'enfant la ressent, pas la subit.

      6. VOCABULAIRE ADAPTÉ : Adapté à l'âge, mais jamais simplet.
         Les enfants aiment les grands mots quand le contexte les rend compréhensibles.

      7. FIN OBLIGATOIRE : L'histoire doit TOUJOURS se terminer complètement.
         Ne t'arrête JAMAIS en plein milieu d'une phrase ou d'une scène.
         Si tu approches de la limite de tokens, écris l'épilogue immédiatement.
         Une histoire sans fin est un échec — la conclusion est non-négociable.
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

    # Instructions de format — structure obligatoire avec début et fin explicites
    prompt += <<~FORMAT

      FORMAT OBLIGATOIRE — respecte cette structure à la lettre :

      [LIGNE 1] Titre accrocheur (sans "Titre :" ni "#")

      ## Chapitre 1 — [titre court]
      (Début : pose le décor, présente les héros EN ACTION, établit l'enjeu clairement)

      ## Chapitre 2 — [titre court]
      (Développement : obstacles, retournements, montée de tension, alliance)

      ## Chapitre 3 — [titre court]
      (Climax : moment de tension maximale, le héros fait face à son défi)

      ## Épilogue
      (OBLIGATOIRE — résolution complète, retour au calme, leçon vécue naturellement)
      (Cette section DOIT exister et DOIT conclure l'histoire de façon satisfaisante)
      (Termine TOUJOURS par une phrase de conclusion mémorable — jamais en plein milieu d'une phrase)

      RÈGLE ABSOLUE : l'histoire doit avoir une FIN COMPLÈTE.
      Ne t'arrête JAMAIS en plein milieu d'une phrase ou d'un paragraphe.
      Si tu approches de la limite, rédige l'épilogue immédiatement.
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
  # 200 mots/min × durée × ~1.5 tokens/mot (français) + marge confortable
  # On triple la marge pour que la fin de l'histoire ne soit jamais coupée
  # Groq (Llama 3.3 70B) supporte jusqu'à 8000 tokens de contexte
  def tokens_for_duration
    { 5 => 3500, 10 => 6000, 15 => 8000 }.fetch(@story.duration_minutes.to_i, 3500)
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
