class GenerateAudioJob < ApplicationJob
  # ============================================================
  # Job de génération audio via OpenAI TTS
  # ============================================================
  # Appelé après la génération du texte (GenerateStoryJob).
  # Génère le MP3 de l'histoire complète et l'attache via ActiveStorage.
  # Exécuté en arrière-plan pour éviter le timeout Heroku (30s max).
  #
  # Le résultat est disponible via story.audio_file.attached?
  # Le frontend poll /stories/:id/status pour détecter quand c'est prêt.

  queue_as :default

  # Limite de caractères par appel OpenAI TTS (max = 4096)
  TTS_CHUNK_SIZE = 4000

  def perform(story_id, source: "story", choice_id: nil)
    story = Story.find(story_id)

    # Détermine le texte à lire selon la source
    text = case source
    when "continuation"
      # Texte de la continuation après un choix interactif
      choice = StoryChoice.find_by(id: choice_id)
      choice&.context_chosen
    else
      # Contenu principal de l'histoire
      story.content
    end

    return if text.blank?

    # Client OpenAI — clé différente de Groq utilisé pour la génération de texte
    client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))

    # Découpe le texte en chunks de max TTS_CHUNK_SIZE caractères
    chunks = tts_split_text(text)

    # Génère tous les chunks EN PARALLÈLE via des threads Ruby.
    # Chaque thread fait un appel OpenAI TTS indépendant.
    # On utilise each_with_index pour préserver l'ordre des chunks dans le résultat final.
    # threads.map(&:value) attend la fin de chaque thread et récupère son résultat.
    threads = chunks.each_with_index.map do |chunk, index|
      Thread.new do
        Rails.logger.info("GenerateAudioJob — chunk #{index + 1}/#{chunks.length} en cours")
        client.audio.speech(
          parameters: {
            model:           "tts-1",
            input:           chunk,
            voice:           "nova",
            response_format: "mp3"
          }
        )
      end
    end

    # Attend tous les threads et concatène les MP3 dans l'ordre
    audio_data = threads.map(&:value).join

    # Attache le MP3 à l'histoire ou au choix selon la source
    if source == "continuation" && choice_id
      choice = StoryChoice.find_by(id: choice_id)
      # On stocke l'URL en base pour pouvoir la servir rapidement
      # Pour simplifier, on attache à la story avec un nom distinct
      story.audio_file.attach(
        io:           StringIO.new(audio_data),
        filename:     "histoire_#{story_id}_continuation_#{choice_id}.mp3",
        content_type: "audio/mpeg"
      )
    else
      # Audio principal de l'histoire
      story.audio_file.attach(
        io:           StringIO.new(audio_data),
        filename:     "histoire_#{story_id}.mp3",
        content_type: "audio/mpeg"
      )
    end

    Rails.logger.info("GenerateAudioJob — audio généré pour story ##{story_id} (source: #{source})")

  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("GenerateAudioJob — story ##{story_id} introuvable")
  rescue => e
    Rails.logger.error("GenerateAudioJob — erreur : #{e.message}")
  end

  private

  # Découpe le texte en chunks à la dernière phrase complète avant TTS_CHUNK_SIZE
  def tts_split_text(text)
    chunks    = []
    remaining = text.strip

    while remaining.length > TTS_CHUNK_SIZE
      candidate      = remaining[0, TTS_CHUNK_SIZE]
      last_boundary  = candidate.rindex(/[.!?]\s/)
      cut_at         = last_boundary ? last_boundary + 1 : (candidate.rindex(" ") || TTS_CHUNK_SIZE)

      chunks    << remaining[0, cut_at].strip
      remaining  = remaining[cut_at..].strip
    end

    chunks << remaining unless remaining.empty?
    chunks
  end
end
