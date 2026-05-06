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
    generator      = StoryGeneratorService.new(story)

    story.update!(
      content: content,
      title:   title
    )

    # 5. En mode interactif : extraire et créer le choix depuis le texte
    if story.interactive?
      create_story_choice_from_content(story, content)
    end

    # 6. Marquer l'histoire comme terminée DÈS QUE LE TEXTE EST PRÊT
    # → le Stimulus story_status_controller redirige immédiatement vers la page de lecture
    # → l'utilisateur peut lire pendant que le prompt image et l'illustration se génèrent
    # IMPORTANT : on ne fait plus le 2ème appel Groq (image_scene_prompt) avant ce point
    # pour éviter ~5s de délai inutile avant que l'utilisateur puisse lire.
    story.update!(status: :completed)

    # 7. Vérifier si l'utilisateur mérite de nouveaux badges (texte disponible = histoire comptée)
    Badge.check_and_award(story.child.user)

    # 8. Lancer l'audio ET l'image EN PARALLÈLE dans deux threads Ruby distincts.
    #
    # Pourquoi des threads et non perform_later ?
    # Avec perform_later, le job audio est mis en file d'attente — il peut démarrer
    # immédiatement sur un thread libre de Solid Queue, mais rien ne le garantit.
    # Avec Thread.new, le travail commence IMMÉDIATEMENT dans ce processus.
    #
    # Les deux tâches (audio ~25s, image ~35-60s) tournent en parallèle :
    # → l'audio sera prêt AVANT que l'image soit terminée
    # → quand GenerateStoryJob se termine, les deux sont garantis finis
    # → l'utilisateur peut lire ET cliquer "Lire" dès qu'il arrive sur la page

    # Thread 1 : génération audio TTS (OpenAI nova)
    audio_thread = Thread.new do
      # On instancie un nouveau job et on l'exécute directement (sans passer par la file)
      GenerateAudioJob.new.perform(story.id)
    rescue StandardError => e
      Rails.logger.error("GenerateStoryJob — échec audio thread : #{e.message}")
    end

    # Thread 2 (thread principal) : prompt image + illustration
    # On génère d'abord le prompt image via Groq (~3-5s), puis l'illustration (~30-60s)
    begin
      story.reload  # S'assure que story.content est bien chargé depuis la base
      image_scene = generator.generate_image_scene_prompt
      story.update_column(:image_scene_prompt, image_scene) if image_scene.present?
      Rails.logger.info("GenerateStoryJob — scène image générée : #{image_scene}")

      ImageGeneratorService.new(story).call
      Rails.logger.info("GenerateStoryJob — image générée pour story ##{story_id}")
    rescue StandardError => e
      Rails.logger.error("GenerateStoryJob — échec image pour story ##{story_id} : #{e.message}")
    end

    # Attend que le thread audio soit terminé avant de clore le job
    # (en pratique il est déjà fini car l'image prend plus longtemps)
    audio_thread.join

    Rails.logger.info("GenerateStoryJob — histoire ##{story_id} générée avec succès")
  rescue ActiveRecord::RecordNotFound
    # L'histoire a été supprimée avant la fin du job — on ignore
    Rails.logger.warn("GenerateStoryJob — story ##{story_id} introuvable, job annulé")
  rescue StandardError => e
    # Toute autre erreur : on marque comme échoué
    story&.update(status: :failed)
    Rails.logger.error("GenerateStoryJob — erreur critique : #{e.message}")
    raise  # Re-raise pour que Solid Queue puisse logger l'erreur
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

  # Parse TOUS les blocs [CHOIX] dans le texte généré
  # Le nombre de blocs dépend de la durée : 5min→1, 10min→2, 15min→3
  # Format attendu :
  #   [CHOIX]
  #   Question : ...
  #   Option A : ...
  #   Option B : ...
  #   [FIN CHOIX]
  def create_story_choice_from_content(story, content)
    # scan retourne toutes les occurrences du pattern (pas seulement la première)
    blocks = content.scan(/\[CHOIX\](.*?)\[FIN CHOIX\]/m)
    return if blocks.empty?

    # Nombre de choix attendu selon la durée : 5min→1, 10min→2, 15min→3
    # On limite au nombre attendu même si l'IA en a généré plus — évite les doublons
    expected_count = { 5 => 1, 10 => 2, 15 => 3 }.fetch(story.duration_minutes.to_i, 1)
    blocks = blocks.first(expected_count)

    # Crée un StoryChoice pour chaque bloc trouvé
    # step_number indique l'ordre : 1er choix = étape 1, 2ème = étape 2, etc.
    blocks.each_with_index do |captures, index|
      choice_block = captures.first

      question = choice_block.match(/Question\s*:\s*(.+)/i)&.captures&.first&.strip
      option_a = choice_block.match(/Option A\s*:\s*(.+)/i)&.captures&.first&.strip
      option_b = choice_block.match(/Option B\s*:\s*(.+)/i)&.captures&.first&.strip

      next unless question && option_a && option_b

      story.story_choices.create!(
        step_number: index + 1,   # 1-indexé
        question: question,
        option_a: option_a,
        option_b: option_b
      )

      Rails.logger.info("GenerateStoryJob — choix interactif #{index + 1} créé pour story ##{story.id}")
    end
  rescue StandardError => e
    Rails.logger.error("GenerateStoryJob — échec création choix interactifs : #{e.message}")
  end
end
