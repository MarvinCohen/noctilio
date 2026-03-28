class GenerateImageJob < ApplicationJob
  # ============================================================
  # Job de génération d'image en arrière-plan
  # ============================================================
  # Séparé de GenerateStoryJob pour ne pas bloquer la lecture.
  # L'histoire est déjà en statut "completed" quand ce job s'exécute.
  # L'image apparaît progressivement côté client via le skeleton de chargement.
  #
  # Flux :
  # 1. GenerateStoryJob génère le texte → marque completed → lance CE job
  # 2. Ce job appelle ImageGeneratorService → sauvegarde cover_image_url
  # 3. Le navigateur charge l'image depuis Pollinations quand la page est ouverte

  queue_as :default

  def perform(story_id)
    story = Story.find(story_id)

    # Génère et sauvegarde l'URL de l'illustration via Pollinations.ai
    result = ImageGeneratorService.new(story).call

    if result[:success]
      Rails.logger.info("GenerateImageJob — image générée pour story ##{story_id}")
    else
      # L'image est optionnelle — l'histoire reste lisible sans illustration
      Rails.logger.warn("GenerateImageJob — échec image pour story ##{story_id} : #{result[:error]}")
    end
  rescue ActiveRecord::RecordNotFound
    # L'histoire a été supprimée avant la fin du job — on ignore
    Rails.logger.warn("GenerateImageJob — story ##{story_id} introuvable, job annulé")
  rescue StandardError => e
    Rails.logger.error("GenerateImageJob — erreur : #{e.message}")
    # Pas de raise — l'échec d'image ne doit pas faire planter la queue
  end
end
