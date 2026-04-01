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
end
