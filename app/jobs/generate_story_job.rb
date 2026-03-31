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
    content = text_result[:content]
    title   = extract_title(content)

    story.update!(
      content: content,
      title: title
    )

    # 5. En mode interactif : extraire et créer le choix depuis le texte
    if story.interactive?
      create_story_choice_from_content(story, content)
    end

    # 6. Sauvegarder l'URL Pollinations — INSTANTANÉ (construction d'URL + écriture DB, zéro HTTP)
    # On le fait ici, avant completed, pour que l'URL soit présente dès que l'histoire est lisible.
    # Le navigateur chargera l'image depuis Pollinations de façon asynchrone (skeleton → image).
    ImageGeneratorService.new(story).call

    # 7. Marquer l'histoire comme terminée — l'URL d'image est déjà sauvegardée
    story.update!(status: :completed)

    # 8. Vérifier si l'utilisateur mérite de nouveaux badges
    Badge.check_and_award(story.child.user)

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
