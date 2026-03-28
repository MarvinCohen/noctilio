class ImageGeneratorService
  # ============================================================
  # Service de génération d'images — Pollinations.ai (gratuit)
  # ============================================================
  # Génère une illustration style livre d'enfants pour une histoire.
  #
  # Stratégie :
  #   1. Pollinations.ai en priorité — 100% gratuit, zéro clé API
  #      Il suffit d'appeler une URL avec le prompt encodé.
  #   2. DALL-E (OpenAI) en fallback — si OPENAI_API_KEY est configurée
  #
  # Pollinations.ai : https://pollinations.ai
  # Format URL : https://image.pollinations.ai/prompt/{prompt_encodé}?width=1024&height=1024&model=flux
  #
  # Utilisation :
  #   service = ImageGeneratorService.new(story)
  #   result = service.call
  #   # result = { success: true } ou { success: false, error: "..." }

  require "open-uri"
  require "uri"

  # URL de base de Pollinations.ai — pas besoin de clé API
  POLLINATIONS_BASE_URL = "https://image.pollinations.ai/prompt"

  # Modèle Pollinations utilisé
  # "flux" : modèle FLUX, excellente qualité pour les illustrations
  POLLINATIONS_MODEL = "flux"

  # Style visuel cohérent pour toutes les illustrations de l'app
  # Ce texte est ajouté à chaque prompt pour garantir un rendu cohérent
  VISUAL_STYLE = "children book illustration, soft watercolor, pastel colors, " \
                 "hand-drawn style, warm and magical atmosphere, simple background, " \
                 "cute and friendly, safe for kids"

  def initialize(story)
    @story = story
    @child = story.child
  end

  # Génère l'image et l'attache à l'histoire via ActiveStorage
  # Retourne { success: true/false, error: "..." }
  def call
    # Construction du prompt en anglais (Pollinations fonctionne mieux en anglais)
    prompt = build_image_prompt

    # Sauvegarde du prompt utilisé (utile pour débuguer ou régénérer)
    @story.update_column(:image_prompt, prompt)

    # Tentative 1 : Pollinations.ai (gratuit, prioritaire)
    result = generate_with_pollinations(prompt)
    return result if result[:success]

    # Tentative 2 : DALL-E (fallback si clé OpenAI présente)
    # Permet de passer à OpenAI plus tard sans changer de code
    if ENV["OPENAI_API_KEY"].present?
      Rails.logger.info("ImageGeneratorService — Pollinations a échoué, tentative DALL-E")
      return generate_with_dalle(prompt)
    end

    # Les deux ont échoué — l'histoire sera créée sans image
    Rails.logger.warn("ImageGeneratorService — aucune image générée pour story ##{@story.id}")
    { success: false, error: result[:error] }
  end

  private

  # ============================================================
  # Génération via Pollinations.ai (gratuit)
  # ============================================================
  # Pollinations expose une API HTTP simple :
  # GET https://image.pollinations.ai/prompt/{prompt}?width=1024&height=1024&model=flux
  # La réponse est directement le fichier image (JPEG)
  def generate_with_pollinations(prompt)
    # Encode le prompt pour une URL valide (espaces → %20, etc.)
    encoded_prompt = URI.encode_uri_component(prompt)

    # Construction de l'URL avec les paramètres
    # nologo=true : retire le watermark Pollinations
    # enhance=true : améliore automatiquement le prompt pour de meilleurs résultats
    image_url = "#{POLLINATIONS_BASE_URL}/#{encoded_prompt}" \
                "?width=1024&height=1024&model=#{POLLINATIONS_MODEL}&nologo=true&enhance=true"

    # Sauvegarde de l'URL directement en base — Pollinations bloque les requêtes serveur (401)
    # On NE télécharge PAS l'image côté serveur : le navigateur l'affichera directement via <img src="...">
    # L'URL Pollinations est permanente et ne s'expire pas (contrairement à DALL-E)
    @story.update_column(:cover_image_url, image_url)

    Rails.logger.info("ImageGeneratorService — URL Pollinations sauvegardée pour story ##{@story.id}")
    { success: true, url: image_url }
  rescue StandardError => e
    Rails.logger.error("ImageGeneratorService — échec Pollinations : #{e.message}")
    { success: false, error: "Erreur Pollinations : #{e.message}" }
  end

  # ============================================================
  # Génération via DALL-E 3 (OpenAI — payant, fallback)
  # ============================================================
  # Utilisé seulement si OPENAI_API_KEY est configurée dans .env
  def generate_with_dalle(prompt)
    client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])

    response = client.images.generate(
      parameters: {
        prompt: prompt,
        model: "dall-e-3",
        size: "1024x1024",
        quality: "standard",
        style: "natural",
        n: 1
      }
    )

    image_url = response.dig("data", 0, "url")
    return { success: false, error: "DALL-E n'a pas retourné d'URL" } unless image_url

    @story.update_column(:cover_image_url, image_url)
    attach_image_from_url(image_url, "png")

    { success: true, url: image_url }
  rescue StandardError => e
    { success: false, error: "Erreur DALL-E : #{e.message}" }
  end

  # ============================================================
  # Construction du prompt image
  # ============================================================
  # Le prompt est en anglais car Pollinations et DALL-E fonctionnent
  # mieux avec des prompts anglais pour le style illustration
  def build_image_prompt
    scene = world_scene_description

    # Prompt combinant style visuel + scène + personnage
    "#{VISUAL_STYLE}. Scene: #{scene} with a child named #{@child.name}, " \
    "#{@child.age} years old, adventurous and curious. " \
    "Positive, magical, child-friendly image."
  end

  # Description de scène adaptée à chaque univers
  def world_scene_description
    {
      "space"      => "a child in a space suit floating among colorful stars and planets",
      "dinos"      => "a child exploring a prehistoric forest with friendly dinosaurs",
      "princesses" => "a child in a magical castle surrounded by fairy lights and flowers",
      "pirates"    => "a child captain on a pirate ship sailing a turquoise sea",
      "animals"    => "a child in an enchanted forest surrounded by smiling colorful animals"
    }.fetch(@story.world_theme, "a child in a colorful magical world")
  end

  # ============================================================
  # Téléchargement et attachement à ActiveStorage
  # ============================================================
  # Télécharge l'image depuis une URL distante et l'attache à l'histoire.
  # content_type : "jpg" pour Pollinations, "png" pour DALL-E
  def attach_image_from_url(url, extension = "jpg")
    # Ouvre l'URL avec un timeout pour éviter de bloquer le job trop longtemps
    downloaded_file = URI.open(url, read_timeout: 60, open_timeout: 30)

    content_type = extension == "png" ? "image/png" : "image/jpeg"

    # Attache l'image téléchargée à l'histoire via ActiveStorage
    @story.cover_image.attach(
      io: downloaded_file,
      filename: "histoire_#{@story.id}_couverture.#{extension}",
      content_type: content_type
    )
  rescue StandardError => e
    # Si le téléchargement échoue, on garde l'URL comme fallback
    # L'histoire s'affichera quand même, avec l'URL directe comme src
    Rails.logger.error("ImageGeneratorService — échec téléchargement : #{e.message}")
    raise  # On re-raise pour que generate_with_pollinations capture l'erreur
  end
end
