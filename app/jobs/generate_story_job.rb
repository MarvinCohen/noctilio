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
      # En cas d'échec, on enregistre l'erreur et on arrête
      story.update!(status: :failed)
      Rails.logger.error("GenerateStoryJob — échec texte pour story ##{story_id} : #{text_result[:error]}")
      return
    end

    # 4. Parser et sauvegarder le contenu généré
    content        = text_result[:content]
    title          = extract_title(content)

    story.update!(
      content: content,
      title: title
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

    # Image + audio sont réservés au Premium : le gratuit n'a QUE le texte.
    # Pourquoi : ce sont les deux opérations payantes (gpt-image-1 et TTS) ;
    # les réserver au Premium maîtrise le coût et rend l'offre payante désirable.
    # EXCEPTION — offre découverte : la 1re histoire du compte est en accès complet
    # même pour un gratuit (full_experience_for? renvoie true pour la 1re histoire).
    # On regarde le statut du propriétaire de l'histoire (story → child → user).
    if story.child.user.full_experience_for?(story)
      # Lance le job audio en arrière-plan via Solid Queue
      # Il s'exécutera dès qu'un worker sera disponible
      GenerateAudioJob.perform_later(story.id)
      Rails.logger.info("GenerateStoryJob — job audio lancé pour story ##{story_id}")

      # Génère l'image dans ce job (thread principal).
      # Le prompt image est désormais construit de façon DÉTERMINISTE en Ruby par
      # ImageGeneratorService (approche "Portrait du héros") — plus d'appel Groq
      # intermédiaire : moins de latence, pas de trait physique perdu à la réécriture.
      begin
        story.reload # S'assure que story.content est bien chargé depuis la base
        ImageGeneratorService.new(story).call
        Rails.logger.info("GenerateStoryJob — image générée pour story ##{story_id}")
      rescue StandardError => e
        Rails.logger.error("GenerateStoryJob — échec image pour story ##{story_id} : #{e.message}")
      end
    else
      # Gratuit : on s'arrête au texte (pas d'image ni d'audio générés)
      Rails.logger.info("GenerateStoryJob — user gratuit : texte seul (ni image ni audio) pour story ##{story_id}")
    end

    Rails.logger.info("GenerateStoryJob — histoire ##{story_id} générée avec succès")
  rescue ActiveRecord::RecordNotFound
    # L'histoire a été supprimée avant la fin du job — on ignore
    Rails.logger.warn("GenerateStoryJob — story ##{story_id} introuvable, job annulé")
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
