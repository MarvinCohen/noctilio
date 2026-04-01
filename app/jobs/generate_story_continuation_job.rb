class GenerateStoryContinuationJob < ApplicationJob
  # ============================================================
  # Job de génération de la suite d'une histoire interactive
  # ============================================================
  # Appelé quand l'enfant fait un choix interactif.
  # Génère la suite de l'histoire en fonction du choix.

  queue_as :default

  def perform(story_id, story_choice_id)
    # Récupérer l'histoire et le choix
    story        = Story.find(story_id)
    story_choice = StoryChoice.find(story_choice_id)

    # Générer la continuation via le service IA
    result = StoryGeneratorService.new(story).continue_with_choice(story_choice)

    if result[:success]
      # Sauvegarder la suite dans le choix résolu
      story_choice.update!(context_chosen: result[:content])

      # Si la continuation contient un nouveau [CHOIX], le parser et créer le StoryChoice
      # Cela arrive quand il y a plusieurs choix (10 min = 2, 15 min = 3)
      if result[:content].include?("[CHOIX]")
        next_step = story.story_choices.maximum(:step_number).to_i + 1
        parse_new_choice(story, result[:content], next_step)
      end

      # Marquer l'histoire comme terminée de nouveau
      story.update!(status: :completed)

      # Vérifier les badges
      Badge.check_and_award(story.child.user)
    else
      story.update!(status: :completed)
      Rails.logger.error("GenerateStoryContinuationJob — échec : #{result[:error]}")
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("GenerateStoryContinuationJob — enregistrement introuvable")
  end

  private

  # Parse un nouveau bloc [CHOIX] dans le texte de continuation
  # et crée un nouveau StoryChoice pour le prochain tour interactif
  def parse_new_choice(story, content, step_number)
    match = content.match(/\[CHOIX\](.*?)\[FIN CHOIX\]/m)
    return unless match

    block    = match[1]
    question = block.match(/Question\s*:\s*(.+)/i)&.captures&.first&.strip
    option_a = block.match(/Option A\s*:\s*(.+)/i)&.captures&.first&.strip
    option_b = block.match(/Option B\s*:\s*(.+)/i)&.captures&.first&.strip

    return unless question && option_a && option_b

    story.story_choices.create!(
      step_number: step_number,
      question:    question,
      option_a:    option_a,
      option_b:    option_b
    )
    Rails.logger.info("GenerateStoryContinuationJob — nouveau choix #{step_number} créé pour story ##{story.id}")
  rescue StandardError => e
    Rails.logger.error("GenerateStoryContinuationJob — échec parsing choix : #{e.message}")
  end
end
