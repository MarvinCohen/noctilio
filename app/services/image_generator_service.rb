class ImageGeneratorService
  # ============================================================
  # Service de génération d'images
  # ============================================================
  # Génère une illustration style livre d'enfants pour une histoire.
  #
  # Stratégie (ordre de priorité) :
  #   1. fal.ai (FLUX.1 Dev) — si FAL_API_KEY configurée
  #      Meilleure qualité, ~0,025$/image, images permanentes sur CDN
  #   2. DALL-E 3 (OpenAI) — si OPENAI_API_KEY configurée
  #      Bonne qualité, ~0,04$/image
  #   3. Pollinations.ai — gratuit, dernier recours
  #      Qualité variable, URL externe (pas de téléchargement)
  #
  # Utilisation :
  #   service = ImageGeneratorService.new(story)
  #   result = service.call
  #   # result = { success: true } ou { success: false, error: "..." }

  require "open-uri"
  require "uri"
  require "net/http"
  require "json"

  # ----------------------------------------------------------------
  # fal.ai — endpoint synchrone FLUX.1 Dev
  # Documentation : https://fal.ai/models/fal-ai/flux/dev
  # Retourne directement l'image dans la réponse (pas de polling)
  # ----------------------------------------------------------------
  FAL_API_URL = "https://fal.run/fal-ai/flux/dev"

  # ----------------------------------------------------------------
  # Pollinations.ai — fallback gratuit
  # ----------------------------------------------------------------
  POLLINATIONS_BASE_URL = "https://image.pollinations.ai/prompt"
  POLLINATIONS_MODEL    = "flux-schnell"

  # ----------------------------------------------------------------
  # Style visuel cohérent pour toutes les illustrations de l'app
  # Ce texte est ajouté à chaque prompt pour garantir un rendu uniforme
  # ----------------------------------------------------------------
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
    # Construction du prompt en anglais (meilleurs résultats avec tous les services)
    prompt = build_image_prompt

    # Sauvegarde du prompt utilisé (utile pour débuguer ou régénérer)
    @story.update_column(:image_prompt, prompt)

    # Tentative 1 : fal.ai en priorité si la clé est configurée
    # FLUX.1 Dev = meilleure qualité artistique, images stockées sur CDN permanent
    if ENV["FAL_API_KEY"].present?
      Rails.logger.info("ImageGeneratorService — tentative fal.ai pour story ##{@story.id}")
      result = generate_with_fal(prompt)
      return result if result[:success]
      Rails.logger.warn("ImageGeneratorService — fal.ai a échoué : #{result[:error]}, tentative DALL-E")
    end

    # Tentative 2 : DALL-E si la clé OpenAI est configurée
    if ENV["OPENAI_API_KEY"].present?
      Rails.logger.info("ImageGeneratorService — tentative DALL-E pour story ##{@story.id}")
      result = generate_with_dalle(prompt)
      return result if result[:success]
      Rails.logger.warn("ImageGeneratorService — DALL-E a échoué : #{result[:error]}, tentative Pollinations")
    end

    # Tentative 3 : Pollinations.ai (gratuit, dernier recours)
    # Sauvegarde une URL externe — le navigateur charge l'image directement
    Rails.logger.info("ImageGeneratorService — tentative Pollinations pour story ##{@story.id}")
    result = generate_with_pollinations(prompt)
    return result if result[:success]

    # Tous les services ont échoué — l'histoire sera créée sans image
    Rails.logger.warn("ImageGeneratorService — aucune image générée pour story ##{@story.id}")
    { success: false, error: result[:error] }
  end

  private

  # ============================================================
  # Génération via fal.ai (FLUX.1 Dev) — priorité 1
  # ============================================================
  # API REST synchrone : POST avec le prompt → reçoit l'URL de l'image
  # Auth : header "Authorization: Key FAL_API_KEY"
  # Réponse JSON : { "images": [{ "url": "https://...", ... }] }
  def generate_with_fal(prompt)
    # Prépare la requête HTTP vers l'endpoint fal.ai
    uri  = URI(FAL_API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = true       # fal.ai utilise HTTPS
    http.read_timeout = 120       # 120s max — FLUX peut prendre ~10-30s
    http.open_timeout = 10        # 10s pour établir la connexion

    # Construit la requête POST avec les paramètres de génération
    request = Net::HTTP::Post.new(uri.path)
    request["Authorization"] = "Key #{ENV['FAL_API_KEY']}"  # Auth fal.ai
    request["Content-Type"]  = "application/json"

    request.body = {
      prompt: prompt,
      image_size:          "landscape_4_3",  # Format paysage — idéal pour couverture de livre
      num_inference_steps: 28,               # Qualité/vitesse — 28 = bon compromis
      guidance_scale:      3.5,              # Fidélité au prompt — valeur recommandée par fal.ai
      num_images:          1,                # Une seule image par histoire
      enable_safety_checker: true            # Filtre de sécurité — obligatoire pour app enfants
    }.to_json

    # Exécute la requête et parse la réponse JSON
    response = http.request(request)
    body     = JSON.parse(response.body)

    # Vérifie que la réponse contient bien une image
    unless response.code == "200" && body["images"]&.first&.dig("url")
      error_msg = body["detail"] || body["error"] || "Réponse inattendue (code #{response.code})"
      return { success: false, error: "fal.ai : #{error_msg}" }
    end

    # Récupère l'URL permanente de l'image sur le CDN fal.ai
    image_url = body["images"].first["url"]

    # Sauvegarde l'URL en base et télécharge l'image dans ActiveStorage
    @story.update_column(:cover_image_url, image_url)
    attach_image_from_url(image_url, "png")

    Rails.logger.info("ImageGeneratorService — fal.ai OK pour story ##{@story.id} : #{image_url}")
    { success: true, url: image_url }
  rescue StandardError => e
    Rails.logger.error("ImageGeneratorService — échec fal.ai : #{e.message}")
    { success: false, error: "Erreur fal.ai : #{e.message}" }
  end

  # ============================================================
  # Génération via DALL-E 3 (OpenAI) — priorité 2
  # ============================================================
  # Utilisé seulement si OPENAI_API_KEY est configurée dans .env
  def generate_with_dalle(prompt)
    client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])

    response = client.images.generate(
      parameters: {
        prompt:  prompt,
        model:   "dall-e-3",
        size:    "1024x1024",
        quality: "standard",
        style:   "natural",
        n:       1
      }
    )

    image_url = response.dig("data", 0, "url")
    return { success: false, error: "DALL-E n'a pas retourné d'URL" } unless image_url

    # Sauvegarde l'URL et télécharge l'image dans ActiveStorage
    @story.update_column(:cover_image_url, image_url)
    attach_image_from_url(image_url, "png")

    { success: true, url: image_url }
  rescue StandardError => e
    { success: false, error: "Erreur DALL-E : #{e.message}" }
  end

  # ============================================================
  # Génération via Pollinations.ai — priorité 3 (dernier recours)
  # ============================================================
  # API simple : construire une URL GET avec le prompt encodé
  # Pollinations bloque les requêtes serveur → on sauvegarde l'URL directement
  # Le navigateur chargera l'image côté client via <img src="...">
  def generate_with_pollinations(prompt)
    # Encode le prompt pour une URL valide (espaces → %20, etc.)
    encoded_prompt = URI.encode_uri_component(prompt)

    # Construction de l'URL avec les paramètres
    # 768x512 : format paysage, plus rapide à générer
    # nologo=true : retire le watermark Pollinations
    image_url = "#{POLLINATIONS_BASE_URL}/#{encoded_prompt}" \
                "?width=768&height=512&model=#{POLLINATIONS_MODEL}&nologo=true&enhance=false"

    # On sauvegarde uniquement l'URL — pas de téléchargement côté serveur
    @story.update_column(:cover_image_url, image_url)

    Rails.logger.info("ImageGeneratorService — URL Pollinations sauvegardée pour story ##{@story.id}")
    { success: true, url: image_url }
  rescue StandardError => e
    Rails.logger.error("ImageGeneratorService — échec Pollinations : #{e.message}")
    { success: false, error: "Erreur Pollinations : #{e.message}" }
  end

  # ============================================================
  # Construction du prompt image
  # ============================================================
  # Le prompt utilise le titre de l'histoire ET un moment clé extrait du texte
  # pour générer une illustration personnalisée, pas générique.
  # En anglais car tous les modèles fonctionnent mieux en anglais.
  def build_image_prompt
    # Extrait une scène dramatique du milieu de l'histoire (souvent le climax)
    key_moment = extract_key_moment

    # Construit la description des héros avec leurs caractéristiques physiques
    # avatar_description inclut les traits physiques (lunettes, couleur cheveux, etc.)
    hero_descriptions = @story.all_children.map do |child|
      # Traduit la description en anglais pour de meilleurs résultats
      "a child named #{child.name}, #{child.age} years old" +
        (child.child_description.present? ? ", #{child.child_description}" : "")
    end.join(" and ")

    # Combine : style visuel + scène clé + description précise des héros
    prompt = "#{VISUAL_STYLE}. "
    prompt += "Key scene: #{key_moment}. " if key_moment.present?
    prompt += "Heroes: #{hero_descriptions}. "
    prompt += "The illustration must show all the heroes together in the same scene. "
    prompt += "Positive, epic, child-friendly image."
    prompt
  end

  # Extrait un moment clé de l'histoire pour personnaliser l'illustration
  # On prend un paragraphe vers les 2/3 du texte (souvent le moment dramatique)
  def extract_key_moment
    return "" if @story.content.blank?

    # Nettoie le contenu : retire le bloc [CHOIX] et les lignes de titre markdown
    # NOTE : on utilise [#]{1,3} au lieu de #{1,3} pour éviter l'interpolation Ruby
    clean = @story.content
                  .gsub(/\[CHOIX\].*?\[FIN CHOIX\]/m, "")
                  .gsub(/^[#]{1,3} .+$/, "")
                  .strip

    # Récupère tous les paragraphes non vides
    paragraphs = clean.split(/\n\n+/).map(&:strip).reject(&:empty?)
    return "" if paragraphs.empty?

    # Prend le paragraphe situé aux 2/3 du texte (zone climax habituelle)
    climax_index = (paragraphs.length * 2 / 3).clamp(0, paragraphs.length - 1)
    moment = paragraphs[climax_index].gsub(/\n/, " ").strip

    # Limite à 200 caractères pour ne pas dépasser la longueur maximale du prompt
    moment.length > 200 ? moment[0..200].rstrip + "..." : moment
  end

  # ============================================================
  # Téléchargement et attachement à ActiveStorage
  # ============================================================
  # Télécharge l'image depuis une URL distante et l'attache à l'histoire.
  # Utilisé par fal.ai et DALL-E (pas Pollinations qui bloque les requêtes serveur)
  def attach_image_from_url(url, extension = "png")
    # Ouvre l'URL avec un timeout pour éviter de bloquer le job trop longtemps
    downloaded_file = URI.open(url, read_timeout: 60, open_timeout: 30)

    content_type = extension == "png" ? "image/png" : "image/jpeg"

    # Attache l'image téléchargée à l'histoire via ActiveStorage
    @story.cover_image.attach(
      io:           downloaded_file,
      filename:     "histoire_#{@story.id}_couverture.#{extension}",
      content_type: content_type
    )
  rescue StandardError => e
    # Si le téléchargement échoue, l'URL est déjà sauvegardée en base comme fallback
    Rails.logger.error("ImageGeneratorService — échec téléchargement : #{e.message}")
    raise  # Re-raise pour que la méthode appelante capture l'erreur
  end
end
