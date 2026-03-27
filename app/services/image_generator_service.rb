class ImageGeneratorService
  # ============================================================
  # Service de génération d'images via OpenAI DALL-E
  # ============================================================
  # Génère une illustration style livre d'enfants pour une histoire.
  # L'image est générée via DALL-E 3, puis téléchargée immédiatement
  # car l'URL expire après 1 heure.
  #
  # Utilisation :
  #   service = ImageGeneratorService.new(story)
  #   result = service.call
  #   # result = { success: true, url: "https://...", local_path: nil }

  # Modèle DALL-E utilisé pour la génération d'images
  # dall-e-3 offre la meilleure qualité pour les illustrations enfants
  IMAGE_MODEL = "dall-e-3"

  # Style visuel cohérent pour toutes les illustrations de l'app
  VISUAL_STYLE = "illustration style livre d'enfants, aquarelle douce, couleurs pastel, " \
                 "trait dessiné à la main, ambiance chaleureuse et féérique, fond simple"

  def initialize(story)
    @story = story
    @child = story.child

    # Initialisation du client OpenAI
    @client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY"))
  end

  # Génère l'image et la télécharge dans ActiveStorage
  # Retourne { success: true/false, error: "..." }
  def call
    # 1. Construire le prompt pour l'image
    prompt = build_image_prompt

    # 2. Appeler l'API DALL-E
    response = @client.images.generate(
      parameters: {
        prompt: prompt,
        model: IMAGE_MODEL,
        size: "1024x1024",      # Format carré pour les cartes d'histoires
        quality: "standard",    # Standard = moins cher, suffisant pour MVP
        style: "natural",       # "natural" est mieux pour le style illustration
        n: 1                    # DALL-E 3 ne supporte qu'une image à la fois
      }
    )

    # 3. Récupérer l'URL de l'image générée
    image_url = response.dig("data", 0, "url")
    revised_prompt = response.dig("data", 0, "revised_prompt")

    unless image_url
      return { success: false, error: "DALL-E n'a pas retourné d'URL" }
    end

    # 4. Sauvegarder le prompt utilisé (pour régénérer si besoin)
    @story.update_column(:image_prompt, revised_prompt || prompt)
    @story.update_column(:cover_image_url, image_url)

    # 5. Télécharger et attacher l'image à ActiveStorage
    # IMPORTANT : l'URL expire après 1 heure — on télécharge tout de suite
    attach_image_from_url(image_url)

    { success: true, url: image_url }
  rescue OpenAI::Error => e
    { success: false, error: "Erreur DALL-E : #{e.message}" }
  rescue StandardError => e
    { success: false, error: "Erreur inattendue : #{e.message}" }
  end

  private

  # Construit le prompt pour l'illustration
  # On utilise les informations de l'histoire pour créer une image cohérente
  def build_image_prompt
    world_label = @story.world_label
    child_name  = @child.name

    # Description visuelle de base selon l'univers
    scene_description = world_scene_description

    # Prompt final combinant style, scène et personnage
    "#{VISUAL_STYLE}. Scène : #{scene_description} avec #{child_name}, " \
    "un enfant de #{@child.age} ans plein d'aventure. " \
    "Univers : #{world_label}. " \
    "Image positive, magique et adaptée aux enfants en bas âge."
  end

  # Retourne une description de scène selon l'univers de l'histoire
  def world_scene_description
    {
      "space"      => "Un enfant en combinaison spatiale flottant parmi les étoiles et les planètes colorées",
      "dinos"      => "Un enfant explorant une forêt préhistorique avec des dinosaures amicaux",
      "princesses" => "Un enfant dans un château magique entouré de lumières féeriques",
      "pirates"    => "Un enfant capitaine sur un navire pirate voguant sur une mer turquoise",
      "animals"    => "Un enfant dans une forêt enchantée entouré d'animaux souriants et colorés"
    }.fetch(@story.world_theme, "Un enfant dans un monde magique et coloré")
  end

  # Télécharge l'image depuis l'URL OpenAI et l'attache à ActiveStorage
  # C'est crucial de le faire immédiatement car l'URL expire après 1h
  def attach_image_from_url(url)
    require "open-uri"

    # Ouvre l'URL distante (téléchargement)
    downloaded_file = URI.open(url, read_timeout: 30)

    # Attache le fichier téléchargé à l'histoire via ActiveStorage
    @story.cover_image.attach(
      io: downloaded_file,
      filename: "histoire_#{@story.id}_couverture.png",
      content_type: "image/png"
    )
  rescue StandardError => e
    # Si le téléchargement échoue, on garde l'URL comme fallback
    Rails.logger.error("ImageGeneratorService — échec du téléchargement : #{e.message}")
  end
end
