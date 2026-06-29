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

      # Extraire la phrase de scène [SCENE] (moment fort de CETTE suite) AVANT
      # de nettoyer : elle servira à générer une illustration fidèle à la suite.
      image_scene = extract_scene(content)

      # On retire les blocs techniques ([CHOIX] ET [SCENE]) du texte affiché : la
      # vue rend context_chosen via simple_format (qui ne nettoie pas le markdown),
      # donc sans ce gsub les blocs bruts s'afficheraient dans l'histoire lue.
      clean_text = content
                   .gsub(/\[CHOIX\].*?\[FIN CHOIX\]/m, "")
                   .gsub(/\[SCENE\].*?\[FIN SCENE\]/m, "")
                   .strip

      # Sauvegarder la suite (nettoyée) + la scène dans le choix résolu
      story_choice.update!(context_chosen: clean_text, image_scene: image_scene)

      # Créer le choix suivant si la continuation en proposait un.
      # Idempotence : on recherche d'abord un choix existant pour cette étape
      # (story_id + step_number), et on ne le crée QUE s'il n'existe pas encore.
      # Cela évite un doublon si le job est rejoué (retry, double soumission).
      # L'index unique composite (story_id, step_number) ajouté en migration sert
      # de filet de sécurité ultime côté base.
      if next_choice_attrs
        next_step = story_choice.step_number + 1
        # find_or_create_by sur la clé (story_id, step_number) : si le choix de
        # cette étape existe déjà, on ne recrée rien. Les autres attributs (question,
        # options) ne sont renseignés qu'à la création, via le bloc.
        story.story_choices.find_or_create_by!(step_number: next_step) do |choice|
          choice.question = next_choice_attrs[:question]
          choice.option_a = next_choice_attrs[:option_a]
          choice.option_b = next_choice_attrs[:option_b]
        end
        Rails.logger.info("GenerateStoryContinuationJob — choix #{next_step} assuré pour story ##{story_id}")
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

      # ILLUSTRATION DE LA SUITE — image fidèle au moment fort de CE passage.
      # On la génère seulement si le LLM a fourni une scène ET que l'utilisateur
      # a droit aux illustrations (Essentiel/Premium ou 1re histoire offerte).
      # L'image est attachée AU CHOIX (story_choice.illustration), sans toucher
      # à la couverture d'intro de l'histoire. On capture les erreurs : un échec
      # d'image ne doit pas casser la continuation déjà sauvegardée.
      if image_scene.present? && story.child.user.illustrations_for?(story)
        begin
          ImageGeneratorService.new(story, story_choice: story_choice).call
          Rails.logger.info("GenerateStoryContinuationJob — illustration générée pour le choix ##{story_choice.id}")
        rescue StandardError => e
          Rails.logger.error("GenerateStoryContinuationJob — échec illustration choix ##{story_choice.id} : #{e.message}")
        end
      end
    else
      story.update!(status: :completed)
      Rails.logger.error("GenerateStoryContinuationJob — échec : #{result[:error]}")
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("GenerateStoryContinuationJob — enregistrement introuvable")
  end

  private

  # Extrait la phrase du bloc [SCENE]...[FIN SCENE] de la continuation (moment fort
  # de CETTE suite, en anglais). Retourne la phrase nettoyée ou nil si absente
  # (→ pas d'illustration de suite générée, aucune régression).
  def extract_scene(content)
    scene = content.match(/\[SCENE\](.*?)\[FIN SCENE\]/m)&.captures&.first
    scene&.strip.presence
  end

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
