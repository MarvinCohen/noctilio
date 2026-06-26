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
      content = result[:content]

      # La continuation peut se terminer par un NOUVEAU bloc [CHOIX] (étape
      # intermédiaire) qui devient le choix suivant de l'aventure.
      next_choice_attrs = extract_choice(content)

      # On retire le bloc [CHOIX] du texte affiché : la vue rend context_chosen
      # via simple_format (qui ne nettoie pas le markdown), donc sans ce gsub le
      # bloc brut "[CHOIX] Question : ..." s'afficherait dans l'histoire.
      clean_text = content.gsub(/\[CHOIX\].*?\[FIN CHOIX\]/m, "").strip

      # Sauvegarder la suite (nettoyée) dans le choix résolu
      story_choice.update!(context_chosen: clean_text)

      # Créer le choix suivant si la continuation en proposait un
      if next_choice_attrs
        story.story_choices.create!(next_choice_attrs.merge(step_number: story_choice.step_number + 1))
        Rails.logger.info("GenerateStoryContinuationJob — choix #{story_choice.step_number + 1} créé pour story ##{story_id}")
      end

      # Pré-génère l'audio de la SUITE pour un enchaînement fluide (Partie B).
      # On lance le TTS dès que le texte de la continuation est écrit : ainsi, quand
      # l'enfant finit d'écouter le passage en cours, l'audio de la suite est déjà
      # prêt (ou presque) et la lecture s'enchaîne sans coupure ni retour au début.
      # Audio réservé au Premium (ou 1re histoire offerte) car le TTS coûte.
      # Le mode interactif est lui-même Premium-only, donc audio_for? est cohérent.
      # source: "continuation" + choice_id → GenerateAudioJob lit choice.context_chosen
      # et attache le MP3 à choice.audio_file (pas à story.audio_file).
      if story.child.user.audio_for?(story)
        GenerateAudioJob.perform_later(story.id, source: "continuation", choice_id: story_choice.id)
        Rails.logger.info("GenerateStoryContinuationJob — audio de la suite lancé pour le choix ##{story_choice.id}")
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

  # Extrait le 1er bloc [CHOIX] d'un texte et retourne un hash d'attributs
  # (question, option_a, option_b) prêt pour StoryChoice, ou nil si pas de bloc
  # valide. Utilisé pour créer le choix suivant à partir d'une continuation.
  def extract_choice(content)
    block = content.match(/\[CHOIX\](.*?)\[FIN CHOIX\]/m)&.captures&.first
    return nil if block.blank?

    question = block.match(/Question\s*:\s*(.+)/i)&.captures&.first&.strip
    option_a = block.match(/Option A\s*:\s*(.+)/i)&.captures&.first&.strip
    option_b = block.match(/Option B\s*:\s*(.+)/i)&.captures&.first&.strip

    return nil unless question && option_a && option_b

    { question: question, option_a: option_a, option_b: option_b }
  end
end
