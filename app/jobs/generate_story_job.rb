class GenerateStoryJob < ApplicationJob
  # ============================================================
  # Job de génération d'histoire en arrière-plan
  # ============================================================
  # Ce job est exécuté par Solid Queue (intégré dans Rails 8).
  # Il orchestre la génération du texte ET de l'image.
  #
  # Flux :
  # 1. Marque l'histoire comme "en cours de génération"
  # 2. Appelle StoryGeneratorService pour le texte (GPT)
  # 3. Parse le titre et les choix interactifs depuis le texte
  # 4. Appelle ImageGeneratorService pour l'image (DALL-E)
  # 5. Marque l'histoire comme "terminée"
  # 6. Vérifie et attribue les badges mérités
  #
  # Gestion des erreurs :
  # — En cas d'échec, le statut passe à "failed" pour informer l'utilisateur

  # File de priorité normale (définie dans config/queue.yml)
  queue_as :default

  # ============================================================
  # Retry automatique des erreurs IA transitoires
  # ============================================================
  # Erreur dédiée levée quand la génération du TEXTE échoue (réseau, surcharge
  # Groq, timeout…). On la distingue de StandardError pour ne rejouer QUE ce cas
  # précis, et pas, par exemple, un bug de programmation.
  class TransientGenerationError < StandardError; end

  # retry_on : Solid Queue replanifie le job en cas de TransientGenerationError.
  #   - attempts: 3 → trois tentatives au total avant d'abandonner.
  #   - wait: :polynomially_longer → délai croissant entre les essais (anti-rafale).
  # Le bloc est exécuté UNE FOIS les tentatives épuisées : on marque alors
  # l'histoire en :failed pour sortir l'utilisateur de l'écran de génération.
  retry_on TransientGenerationError, wait: :polynomially_longer, attempts: 3 do |job, error|
    story_id = job.arguments.first
    Story.find_by(id: story_id)&.update(status: :failed)
    Rails.logger.error("GenerateStoryJob — échec définitif après #{job.executions} tentatives : #{error.message}")
  end

  def perform(story_id)
    # 1. Récupérer l'histoire depuis la base de données
    story = Story.find(story_id)

    # Sécurité : ne pas regénérer une histoire déjà terminée
    return if story.completed?

    # 2. Marquer comme "en cours" pour afficher le spinner côté utilisateur
    story.update!(status: :generating)

    # 3. Générer le texte de l'histoire via GPT
    text_result = StoryGeneratorService.new(story).call

    unless text_result[:success]
      # Échec de la génération de texte : on le traite comme transitoire et on
      # lève TransientGenerationError. Solid Queue rejouera alors le job (jusqu'à
      # 3 fois via retry_on). On NE passe PAS en :failed ici : l'histoire reste
      # en :generating pendant les tentatives, et ne bascule en :failed qu'après
      # épuisement (bloc retry_on ci-dessus). L'utilisateur garde le spinner.
      Rails.logger.warn("GenerateStoryJob — échec texte pour story ##{story_id} : #{text_result[:error]} — nouvelle tentative")
      raise TransientGenerationError, text_result[:error]
    end

    # 4. Parser et sauvegarder le contenu généré
    content        = text_result[:content]
    title          = extract_title(content)

    # 4bis. Extraire le bloc [SCENE] (phrase visuelle EN ANGLAIS du moment fort)
    # AVANT de nettoyer le contenu. Ce bloc est rédigé par le LLM dans la même
    # réponse Groq (zéro latence ajoutée) et servira à composer le prompt image.
    image_scene = extract_scene(content)

    # Puis on RETIRE le bloc [SCENE] du texte affiché : il ne doit JAMAIS
    # apparaître dans l'histoire lue par le parent (même logique que [CHOIX]).
    content = strip_scene_block(content)

    story.update!(
      content: content,
      title: title,
      image_scene: image_scene
    )

    # 5. En mode interactif : extraire et créer le choix depuis le texte
    create_story_choice_from_content(story, content) if story.interactive?

    # 6. Marquer l'histoire comme terminée DÈS QUE LE TEXTE EST PRÊT
    # → le Stimulus story_status_controller redirige immédiatement vers la page de lecture
    # → l'utilisateur peut lire pendant que le prompt image et l'illustration se génèrent
    # IMPORTANT : on ne fait plus le 2ème appel Groq (image_scene_prompt) avant ce point
    # pour éviter ~5s de délai inutile avant que l'utilisateur puisse lire.
    story.update!(status: :completed)

    # 7. Vérifier si l'utilisateur mérite de nouveaux badges (texte disponible = histoire comptée)
    Badge.check_and_award(story.child.user)

    # 8. Lancer l'audio via un job séparé, puis générer l'image dans ce job.
    #
    # Pourquoi perform_later plutôt que Thread.new ?
    # Thread.new dans un background job est dangereux :
    #   — partage la connexion Active Record du job parent (non thread-safe)
    #   — les exceptions dans le thread sont silencieusement avalées
    #   — crée des fuites mémoire si le thread ne se termine pas proprement
    # perform_later délègue à Solid Queue qui gère les connexions et les erreurs
    # correctement. L'audio (~25s) et l'image (~35-60s) peuvent se chevaucher
    # si Solid Queue a plusieurs workers configurés.

    # Depuis l'ajout du palier Essentiel, image et audio ne sont plus liés :
    #   — ILLUSTRATION : débloquée dès Essentiel (illustrations_for?).
    #   — AUDIO : réservé au Premium (audio_for?).
    # Dans les deux cas, l'offre découverte (1re histoire offerte) reste en accès
    # complet même pour un gratuit. On regarde le statut du propriétaire de
    # l'histoire (story → child → user).
    user = story.child.user

    # AUDIO (Premium uniquement) — lancé en arrière-plan via Solid Queue.
    if user.audio_for?(story)
      GenerateAudioJob.perform_later(story.id)
      Rails.logger.info("GenerateStoryJob — job audio lancé pour story ##{story_id}")
    else
      Rails.logger.info("GenerateStoryJob — pas d'audio (réservé Premium) pour story ##{story_id}")
    end

    # ILLUSTRATION (Essentiel et Premium) — générée dans ce job (thread principal).
    # Le prompt image est construit de façon DÉTERMINISTE en Ruby par
    # ImageGeneratorService (approche "Portrait du héros") — pas d'appel Groq
    # intermédiaire : moins de latence, pas de trait physique perdu à la réécriture.
    if user.illustrations_for?(story)
      begin
        story.reload # S'assure que story.content est bien chargé depuis la base
        ImageGeneratorService.new(story).call
        Rails.logger.info("GenerateStoryJob — image générée pour story ##{story_id}")
      rescue StandardError => e
        Rails.logger.error("GenerateStoryJob — échec image pour story ##{story_id} : #{e.message}")
      end
    else
      # Gratuit (hors 1re histoire) : on s'arrête au texte, pas d'image générée.
      Rails.logger.info("GenerateStoryJob — user gratuit : texte seul (pas d'image) pour story ##{story_id}")
    end

    Rails.logger.info("GenerateStoryJob — histoire ##{story_id} générée avec succès")
  rescue ActiveRecord::RecordNotFound
    # L'histoire a été supprimée avant la fin du job — on ignore
    Rails.logger.warn("GenerateStoryJob — story ##{story_id} introuvable, job annulé")
  rescue TransientGenerationError
    # Erreur transitoire de génération de texte : on la laisse remonter telle quelle
    # pour que retry_on (déclaré plus haut) la capte et replanifie le job.
    # On NE passe surtout PAS en :failed ici (sinon l'histoire serait marquée échouée
    # dès la 1re tentative, alors qu'on veut la rejouer).
    raise
  rescue StandardError => e
    # Toute autre erreur : on marque comme échoué
    story&.update(status: :failed)
    Rails.logger.error("GenerateStoryJob — erreur critique : #{e.message}")
    raise # Re-raise pour que Solid Queue puisse logger l'erreur
  end

  private

  # Extrait le titre de l'histoire depuis la première ligne du texte généré
  # Le GPT place le titre sur la première ligne
  def extract_title(content)
    first_line = content.lines.first&.strip
    return "Mon histoire magique" if first_line.blank?

    # Nettoyage : enlève les caractères spéciaux de titre (#, *, **, etc.)
    first_line.gsub(/^[#*\s]+/, "").gsub(/[*#]+$/, "").strip
  end

  # Extrait la phrase de scène du bloc [SCENE]...[FIN SCENE] généré par le LLM.
  #
  # Le LLM termine sa réponse par un bloc dédié contenant UNE phrase en anglais
  # qui décrit le moment le plus visuel de l'histoire (action, posture, décor),
  # SANS décrire les traits physiques de l'enfant (gérés en Ruby).
  #
  # Format attendu :
  #   [SCENE]
  #   Léa reaching toward a glowing crystal planet in zero gravity...
  #   [FIN SCENE]
  #
  # Retourne la phrase nettoyée (strip) ou nil si le bloc est absent
  # (→ fallback automatique sur le système de prompt actuel, aucune régression).
  def extract_scene(content)
    # match (et pas scan) : un seul bloc [SCENE] est attendu en fin de réponse
    scene = content.match(/\[SCENE\](.*?)\[FIN SCENE\]/m)&.captures&.first
    scene&.strip.presence
  end

  # Retire le bloc [SCENE]...[FIN SCENE] (et ses marqueurs) du contenu affiché.
  #
  # On supprime le bloc entier puis on nettoie les éventuels sauts de ligne
  # surnuméraires laissés en fin de texte, pour que l'histoire lue reste propre.
  def strip_scene_block(content)
    content.gsub(/\[SCENE\].*?\[FIN SCENE\]/m, "").rstrip
  end

  # Parse le PREMIER bloc [CHOIX] du texte généré et crée le choix d'étape 1.
  #
  # Modèle séquentiel ("un choix à la fois") : la génération initiale ne contient
  # qu'UN seul choix (celui qui clôt l'intro). Les choix suivants sont créés par
  # GenerateStoryContinuationJob après chaque décision de l'enfant.
  #
  # Format attendu :
  #   [CHOIX]
  #   Question : ...
  #   Option A : ...
  #   Option B : ...
  #   [FIN CHOIX]
  def create_story_choice_from_content(story, content)
    # match (et pas scan) : on ne s'intéresse qu'au 1er bloc [CHOIX]
    block = content.match(/\[CHOIX\](.*?)\[FIN CHOIX\]/m)&.captures&.first
    return if block.blank?

    question = block.match(/Question\s*:\s*(.+)/i)&.captures&.first&.strip
    option_a = block.match(/Option A\s*:\s*(.+)/i)&.captures&.first&.strip
    option_b = block.match(/Option B\s*:\s*(.+)/i)&.captures&.first&.strip

    return unless question && option_a && option_b

    # 1er choix de l'aventure → step_number 1
    story.story_choices.create!(
      step_number: 1,
      question: question,
      option_a: option_a,
      option_b: option_b
    )

    Rails.logger.info("GenerateStoryJob — choix interactif 1 créé pour story ##{story.id}")
  rescue StandardError => e
    Rails.logger.error("GenerateStoryJob — échec création choix interactif : #{e.message}")
  end
end
