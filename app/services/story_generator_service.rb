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

    # Appelle le même moteur de continuation avec l'option inversée.
    # request_next_choice: false → la timeline alternative ne propose JAMAIS de
    # nouveau choix cliquable (c'est une exploration en lecture seule du "et si...").
    response = @client.chat(
      parameters: {
        model: MODEL,
        messages: build_continuation_messages(alternative_choice, request_next_choice: false),
        temperature: 0.85,
        max_tokens: 600,
        top_p: 0.9
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
        # Budget proportionnel à la durée (voir continuation_tokens).
        # Avant : 600 tokens fixes → trop court face à la cible ~875 mots
        # demandée dans le prompt, d'où des suites coupées en plein milieu de phrase.
        max_tokens: continuation_tokens,
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
  rescue StandardError => e
    # Filet de sécurité : toute autre erreur (réseau, parsing, timeout…) est
    # capturée et renvoyée sous forme de résultat d'échec, comme le fait déjà
    # generate_alternative_timeline plus haut. Sans ce rescue, une erreur non
    # OpenAI faisait planter GenerateStoryContinuationJob sans repasser l'histoire
    # en :completed, laissant l'enfant bloqué sur l'écran de génération.
    { success: false, error: "Erreur inattendue : #{e.message}" }
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
    messages << { role: "user", content: parent_context_prompt } if @story.sequel? && @story.parent_story.present?

    messages
  end

  # Prompt système — personnage et règles NON-NÉGOCIABLES de l'IA
  # IMPORTANT : les directives critiques sont EN PREMIER (Llama pèse plus les premiers tokens)
  def system_prompt
    # Règle 7 (clôture) — elle DIFFÈRE selon le mode :
    # - Mode classique : l'histoire doit toujours être conclue (épilogue obligatoire).
    # - Mode interactif : l'histoire NE doit PAS être conclue d'office — elle
    #   s'arrête sur un choix. C'est l'instruction du message utilisateur qui dira,
    #   au cas par cas, s'il faut s'arrêter sur un [CHOIX] ou écrire la conclusion.
    closing_rule = if @story.interactive?
                     <<~RULE
                       7. NE COUPE JAMAIS EN PLEIN MILIEU : termine toujours ta phrase et ta scène
                          proprement. En mode interactif, tu t'arrêtes au moment d'un choix
                          (bloc [CHOIX]) SANS résoudre l'action — SAUF si l'instruction te
                          demande explicitement d'écrire la conclusion finale.
                          Suis à la lettre l'instruction du message utilisateur sur ce point.
                     RULE
                   else
                     <<~RULE
                       7. FIN OBLIGATOIRE : L'histoire doit TOUJOURS se terminer complètement.
                          Ne t'arrête JAMAIS en plein milieu d'une phrase ou d'une scène.
                          Si tu approches de la limite de tokens, écris l'épilogue immédiatement.
                          Une histoire sans fin est un échec — la conclusion est non-négociable.
                     RULE
                   end

    <<~PROMPT
      Tu es le meilleur conteur d'histoires épiques et magiques pour enfants au monde.
      Tu écris dans le style des grands films d'animation (Pixar, Miyazaki, Disney).

      LANGUE DE L'HISTOIRE (priorité absolue) : écris TOUT le texte de l'histoire
      (titre, chapitres, dialogues, narration) EN #{language_name.upcase}.
      N'utilise AUCUNE autre langue dans le récit, même si ces consignes sont
      rédigées en français — ces consignes te guident, elles ne se retrouvent pas
      dans l'histoire.

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

      6. NIVEAU DE LECTURE ADAPTÉ À L'ÂGE (#{@child.age} ans) — calibre précisément
         la longueur des phrases et la richesse du vocabulaire selon ces consignes :
      #{reading_level_guidance}
         Garde le récit beau et immersif : adapter le niveau ne veut pas dire l'appauvrir.

      #{closing_rule}

      8. ILLUSTRATION — BLOC [SCENE] OBLIGATOIRE : tout à la fin de ta réponse,
         APRÈS l'histoire (et après le bloc [CHOIX] s'il existe), ajoute EXACTEMENT
         ce bloc, chaque marqueur sur sa propre ligne :
         [SCENE]
         une SEULE phrase EN ANGLAIS décrivant le moment le plus visuel et fort de
         l'histoire : ce que FAIT le héros, l'action clé, sa posture et son émotion,
         et le décor autour. NE DÉCRIS PAS les traits physiques de l'enfant
         (ni cheveux, ni yeux, ni peau) — uniquement l'action et la scène.
         [FIN SCENE]
         Ce bloc sert à générer l'illustration ; il ne fait PAS partie du récit lu.
    PROMPT
  end

  # ============================================================
  # reading_level_guidance — consignes de niveau de lecture par tranche d'âge
  # ============================================================
  # Pourquoi : la simple mention "adapté à l'âge" est trop vague pour le modèle.
  # On donne ici des règles CONCRÈTES (longueur de phrase, vocabulaire, structure)
  # calées sur l'âge réel de l'enfant (@child.age), pour aider un apprenti lecteur
  # à suivre le texte tout en gardant un récit immersif.
  # Renvoie un bloc de texte injecté dans la règle 6 du system_prompt.
  def reading_level_guidance
    case @child.age
    when 0..5
      # Tout-petits : on privilégie la clarté absolue.
      <<~LEVEL.strip
        - Phrases TRÈS courtes (5 à 10 mots), une seule idée par phrase.
           - Vocabulaire concret du quotidien ; évite les mots abstraits ou rares.
           - Répétitions douces (mots, structures) qui rassurent et rythment le récit.
           - Évite les subordonnées : préfère des phrases simples enchaînées.
      LEVEL
    when 6..8
      # Lecteurs débutants/intermédiaires : on enrichit progressivement.
      <<~LEVEL.strip
        - Phrases de longueur moyenne, avec quelques subordonnées simples.
           - Vocabulaire plus riche : tu peux introduire des mots nouveaux,
             mais rends-les compréhensibles par le contexte immédiat.
           - Des dialogues vivants pour porter l'action et le caractère.
      LEVEL
    else
      # Lecteurs confirmés (9 ans et +) : on vise la richesse littéraire.
      <<~LEVEL.strip
        - Phrases plus longues et variées dans leur rythme.
           - Vocabulaire soutenu, métaphores et images, sans jamais devenir abscons.
           - Structures narratives plus complexes et nuances émotionnelles assumées.
      LEVEL
    end
  end

  # Prompt utilisateur — aiguille vers la version interactive ou classique.
  # En interactif, on ne génère que le DÉBUT de l'histoire (jusqu'au 1er choix) ;
  # la suite est produite au fil des choix par GenerateStoryContinuationJob.
  def user_prompt
    value_label = educational_value_label

    # Héros (le principal + d'éventuels héros secondaires de la même famille)
    extra        = @story.extra_children.to_a
    all_heroes   = [@child] + extra
    heroes_desc  = all_heroes.map { |c| "• #{c.avatar_description}" }.join("\n")

    # Nombre de mots visé pour une histoire COMPLÈTE (200 mots/min)
    word_count   = @story.duration_minutes * 200

    # Ligne univers — OBLIGATOIRE quand world_theme est défini.
    # Sans cette contrainte explicite, Groq invente un décor qui ignore l'univers choisi
    # (ex: world_theme "space" → histoire dans une forêt enchantée)
    adventure_section = if @story.world_theme.present?
                          "🌍 UNIVERS OBLIGATOIRE : #{world_theme_prompt_label}\n      🌟 THÈME : #{@story.custom_theme.presence || 'une aventure épique et magique'}"
                        else
                          "🌟 AVENTURE : #{@story.custom_theme.presence || 'une aventure épique et magique'}"
                        end

    if @story.interactive?
      interactive_user_prompt(heroes_desc, adventure_section, value_label, word_count)
    else
      classic_user_prompt(heroes_desc, adventure_section, value_label, word_count)
    end
  end

  # Prompt d'une histoire CLASSIQUE (non interactive) : histoire complète d'un bloc.
  def classic_user_prompt(heroes_desc, adventure_section, value_label, word_count)
    prompt = <<~PROMPT
      PARAMÈTRES DE L'HISTOIRE :

      ⚔️  HÉROS (présents ensemble dès la première phrase) :
      #{heroes_desc}

      #{adventure_section}
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

    prompt
  end

  # Prompt de la 1re partie d'une histoire INTERACTIVE.
  # Objectif : poser le décor + un ÉVÉNEMENT déclencheur qui rend le choix
  # crucial, puis s'arrêter NET sur un unique bloc [CHOIX]. Aucune conclusion.
  def interactive_user_prompt(heroes_desc, adventure_section, value_label, word_count)
    # Nombre total de choix prévus sur toute l'aventure (selon la durée)
    total_choices = interactive_choices_count

    # L'intro ne couvre qu'UN segment de l'histoire (le morceau avant le 1er choix).
    # On répartit le total de mots sur (nb de choix + 1) segments.
    segment_words = word_count / (total_choices + 1)

    <<~PROMPT
      PARAMÈTRES DE L'HISTOIRE INTERACTIVE :

      ⚔️  HÉROS (présents ensemble dès la première phrase) :
      #{heroes_desc}

      #{adventure_section}
      💫 VALEUR À TRANSMETTRE : #{value_label}

      C'est une histoire DONT L'ENFANT EST LE HÉROS : il fera des choix qui
      décident de la suite. Tu n'écris PAS toute l'histoire maintenant — tu
      écris seulement le DÉBUT, jusqu'au premier choix.

      AVANT D'ÉCRIRE, pense étape par étape (ne pas afficher cette réflexion) :
      1. Comment les héros SONT-ILS déjà en action dès la 1ère phrase ?
      2. Quel ÉVÉNEMENT déclencheur fait surgir un vrai dilemme pour le héros ?
      3. Pourquoi les deux options sont-elles aussi tentantes l'une que l'autre
         (pas de "bon" ni de "mauvais" choix évident) ?

      MAINTENANT ÉCRIS LE DÉBUT (environ #{segment_words} mots) :
      — Titre accrocheur sur la première ligne (sans "Titre :" ni "#")
      — Plante le décor et les héros EN ACTION, dans l'univers demandé
      — Fais monter la tension vers un ÉVÉNEMENT qui force une décision
      — ARRÊTE-TOI EXACTEMENT au moment de la décision, sur le bloc [CHOIX]

      RÈGLE ABSOLUE — NE termine PAS l'histoire :
      — PAS d'épilogue, PAS de conclusion, PAS de "ils vécurent heureux".
      — NE résous PAS la situation : le héros est figé devant son choix.
      — Le texte se termine par le bloc [CHOIX] et RIEN après.

      Format du bloc de choix (à placer tout à la fin, une seule fois) :
      [CHOIX]
      Question : (question courte au moment de décider — "Que va faire [héros] ?")
      Option A : (première action possible, audacieuse)
      Option B : (deuxième action possible, tout aussi tentante)
      [FIN CHOIX]

      IMPORTANT — repères techniques : garde les balises [CHOIX], [FIN CHOIX] et
      les étiquettes "Question :", "Option A :", "Option B :" EXACTEMENT telles
      quelles (en français, sans les traduire). SEUL leur contenu (le texte de la
      question et des options) est rédigé dans la langue de l'histoire.
    PROMPT
  end

  # Construit les messages pour la continuation après un choix interactif.
  # N'envoie PAS l'histoire depuis le début — seulement le contexte récent
  # pour que l'IA continue naturellement sans repartir à zéro.
  #
  # request_next_choice : faut-il que la continuation se termine sur un NOUVEAU
  #   bloc [CHOIX] (étape intermédiaire) ou par la conclusion finale ?
  #   - nil (défaut) : calculé automatiquement selon l'étape du choix et le
  #     nombre total de choix prévus pour la durée.
  #   - false : forcé sans nouveau choix (utilisé par les timelines alternatives,
  #     qui sont des explorations en lecture seule, sans branche cliquable).
  def build_continuation_messages(story_choice, request_next_choice: nil)
    # Nombre total de choix prévus sur l'aventure (5min→1, 10min→2, 15min→3)
    total_choices = interactive_choices_count

    # Par défaut : on demande un nouveau choix tant qu'on n'a pas atteint le dernier.
    request_next_choice = story_choice.step_number < total_choices if request_next_choice.nil?

    # Mots visés pour ce passage (~un quart de l'histoire par continuation)
    continuation_words = tokens_for_duration / 4

    # Contexte récent = la fin du passage qui s'est terminé sur CE choix.
    # Pour le 1er choix, c'est l'intro (@story.content). Pour les suivants, c'est
    # la continuation générée après le choix précédent (stockée dans son context_chosen).
    prev_choice    = @story.story_choices.find_by(step_number: story_choice.step_number - 1)
    base_text      = prev_choice&.context_chosen.presence || @story.content.to_s
    recent_context = base_text.last(1500)

    # Héros de l'histoire : principal + éventuels enfants supplémentaires.
    # On les nomme explicitement dans le prompt de continuation car le gabarit de
    # question était au singulier ("Que va faire [héros] ?") → le LLM oubliait les
    # héros secondaires (bug histoire 138 : seul Ismaël apparaissait, Isaac ignoré).
    heroes_names  = @story.all_children.map(&:name).reject(&:blank?)
    # "Ismaël et Isaac" (ou juste "Ismaël" s'il n'y a qu'un héros) pour la consigne.
    heroes_phrase = heroes_names.to_sentence(words_connector: ", ", last_word_connector: " et ")
    # Rappel multi-héros : n'a d'effet que s'il y a 2 héros ou plus (sinon vide).
    multi_heroes_note = if heroes_names.size > 1
                          "Les héros de l'histoire sont : #{heroes_phrase}. " \
                          "Ils vivent l'aventure ENSEMBLE : la suite, la question et " \
                          "les deux options doivent TOUJOURS les impliquer tous, sans " \
                          "jamais en oublier un. "
                        else
                          ""
                        end

    # En-tête commun : titre, fin du passage précédent, choix de l'enfant
    header = <<~HEAD
      L'histoire s'intitule "#{@story.title}".
      #{multi_heroes_note}
      Voici la fin du dernier passage :
      #{recent_context}

      L'enfant a choisi : #{story_choice.chosen_text}
    HEAD

    body = if request_next_choice
             # Étape intermédiaire : on avance ET on s'arrête sur un nouveau dilemme
             <<~BODY
               Continue DIRECTEMENT depuis ce choix (environ #{continuation_words} mots).
               Ne résume pas ce qui s'est passé avant — plonge immédiatement dans l'action.
               Même style cinématographique, même ton.
               Fais monter la tension vers un NOUVEL événement qui force une décision,
               puis ARRÊTE-TOI sur ce nouveau dilemme. PAS de conclusion, PAS d'épilogue.

               Termine par ce bloc, une seule fois, tout à la fin :
               [CHOIX]
               Question : (question courte — "Que vont faire #{heroes_phrase} ?")
               Option A : (première action possible, vécue par TOUS les héros)
               Option B : (deuxième action possible, tout aussi tentante, par TOUS les héros)
               [FIN CHOIX]

               IMPORTANT — repères techniques : garde les balises [CHOIX], [FIN CHOIX]
               et les étiquettes "Question :", "Option A :", "Option B :" EXACTEMENT
               telles quelles (en français, sans les traduire). SEUL leur contenu est
               rédigé dans la langue de l'histoire.
             BODY
           else
             # Dernière étape : on conclut l'histoire
             <<~BODY
               C'est le dernier chapitre — écris une conclusion épique et mémorable
               (environ #{continuation_words} mots).
               Continue DIRECTEMENT depuis ce choix sans résumer ce qui s'est passé avant.
               Le climax doit être intense, la résolution satisfaisante.
               Termine par une leçon vécue naturellement dans l'action — jamais
               expliquée, jamais moralisatrice.
             BODY
           end

    # Rappel du bloc [SCENE] : la règle 8 du system_prompt le demande déjà, mais le
    # body ci-dessus dit "termine par [CHOIX]" / "rien après", ce qui pourrait faire
    # oublier la scène. On réaffirme donc qu'APRÈS tout le reste (y compris [CHOIX]),
    # la réponse se termine par le bloc [SCENE] décrivant le moment fort de CETTE suite.
    scene_reminder = <<~SCENE
      Tout à la fin de ta réponse, APRÈS l'histoire (et après le bloc [CHOIX] s'il
      existe), ajoute EXACTEMENT le bloc [SCENE]...[FIN SCENE] : UNE phrase EN ANGLAIS
      décrivant le moment le plus visuel de CE passage (ce que FAIT le héros, l'action,
      sa posture, son émotion, le décor), SANS décrire ses traits physiques.
    SCENE

    [
      # Le prompt système garde les règles de style (Pixar, structure narrative, etc.)
      { role: "system", content: system_prompt },
      # Un seul message utilisateur : contexte récent + choix + instruction + rappel scène
      { role: "user", content: "#{header}\n#{body}\n#{scene_reminder}" }
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

  # Retourne une description détaillée de l'univers pour le prompt texte
  # La description explicite le cadre visuel et les éléments attendus
  # pour que Groq ne parte pas dans un décor générique (forêt enchantée pour l'espace, etc.)
  def world_theme_prompt_label
    {
      "space" => "L'ESPACE COSMIQUE — l'histoire se passe DANS L'ESPACE ou sur d'autres planètes. " \
                 "Décors obligatoires : vaisseaux spatiaux, planètes, galaxies, étoiles, combinaisons spatiales, " \
                 "stations orbitales, astéroïdes, nébuleuses. PAS de forêt, PAS de château, PAS de mer.",
      "dinos" => "DINOSAURES ET ÈRE PRÉHISTORIQUE — l'histoire se passe dans un monde de dinosaures. " \
                 "Les animaux principaux DOIVENT être des DINOSAURES (T-Rex, Vélociraptor, Brachiosaure, Tricératops...). " \
                 "PAS de dragons, PAS de licornes. Décors : jungle préhistorique, volcans, marécages.",
      "princesses" => "MONDE ENCHANTÉ DES PRINCESSES ET ROYAUMES MAGIQUES — châteaux, royaumes, cours royales, " \
                      "créatures féeriques (fées, licornes), forêts enchantées, sortilèges.",
      "pirates" => "MONDE DES PIRATES ET HAUTE MER — l'histoire se passe en mer. " \
                   "Décors obligatoires : bateaux pirates, îles tropicales, trésors enfouis, port animé, tempêtes marines.",
      "animals" => "MONDE DES ANIMAUX — les personnages secondaires et l'univers tournent autour des animaux. " \
                   "Forêt, savane, océan ou jungle selon le contexte. Les animaux parlent et s'aventurent avec le héros."
    }[@story.world_theme] || @story.world_theme
  end

  # Retourne le nom (en français) de la langue dans laquelle l'IA doit écrire l'histoire.
  # Lue depuis @story.locale, figée à la création (cf. migration add_locale_to_stories) :
  # le job tourne en arrière-plan où I18n.locale retombe à :fr, on ne peut donc PAS
  # se fier à la locale courante — la langue de l'histoire vit sur la Story.
  # Le nom est en français car il est injecté dans le prompt système (lui-même en
  # français) : "écris TOUT le texte EN ANGLAIS". Llama 3.3 est multilingue et suit
  # cette consigne tout en rédigeant le récit dans la langue demandée.
  # Repli sur "français" si la locale est inconnue (sécurité).
  def language_name
    {
      "fr" => "français",
      "en" => "anglais",
      "es" => "espagnol",
      "de" => "allemand",
      "it" => "italien",
      "pt" => "portugais"
    }.fetch(@story.locale.to_s, "français")
  end

  # Retourne le libellé français de la valeur éducative
  def educational_value_label
    {
      "courage" => "le courage",
      "sharing" => "le partage",
      "kindness" => "la gentillesse",
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

  # Budget de tokens pour UNE continuation interactive (un seul passage).
  #
  # Le prompt de continuation vise environ `tokens_for_duration / 4` MOTS.
  # En français, un mot ≈ 1,3 à 1,5 token : il faut donc largement plus de tokens
  # que de mots visés, sinon la suite est coupée en plein milieu (bug observé sur
  # l'histoire 57, où max_tokens valait 600 alors que ~875 mots étaient demandés).
  #
  # On prend la moitié du budget total : assez large pour boucler une conclusion
  # sans risque de troncature, et toujours sous la limite de contexte de Groq.
  #   5 min  → 1750 tokens   (cible ~875 mots)
  #   10 min → 3000 tokens   (cible ~1500 mots)
  #   15 min → 4000 tokens   (cible ~2000 mots)
  def continuation_tokens
    tokens_for_duration / 2
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
