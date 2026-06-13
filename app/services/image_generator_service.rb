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
  require "base64"

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

    # Tentative 1 : DALL-E 3 en priorité — meilleur suivi des prompts complexes
    # (scènes avec robots/mechs, cockpits, rôles multiples personnages)
    if ENV["OPENAI_API_KEY"].present?
      Rails.logger.info("ImageGeneratorService — tentative DALL-E pour story ##{@story.id}")
      result = generate_with_dalle(prompt)
      return result if result[:success]

      Rails.logger.warn("ImageGeneratorService — DALL-E a échoué : #{result[:error]}, tentative fal.ai")
    end

    # Tentative 2 : fal.ai (FLUX.1 Dev) — fallback si DALL-E échoue
    # FLUX.1 Dev = bonne qualité artistique, images stockées sur CDN permanent
    if ENV["FAL_API_KEY"].present?
      Rails.logger.info("ImageGeneratorService — tentative fal.ai pour story ##{@story.id}")
      result = generate_with_fal(prompt)
      return result if result[:success]

      Rails.logger.warn("ImageGeneratorService — fal.ai a échoué : #{result[:error]}, tentative Pollinations")
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
    http.use_ssl = true # fal.ai utilise HTTPS
    http.read_timeout = 120       # 120s max — FLUX peut prendre ~10-30s
    http.open_timeout = 10        # 10s pour établir la connexion

    # Construit la requête POST avec les paramètres de génération
    request = Net::HTTP::Post.new(uri.path)
    request["Authorization"] = "Key #{ENV.fetch('FAL_API_KEY', nil)}" # Auth fal.ai
    request["Content-Type"]  = "application/json"

    # Construit le negative_prompt selon la couleur de peau de chaque héros
    # On bloque l'opposé de la couleur spécifiée pour forcer le modèle à la respecter
    skin_negatives = @story.all_children.filter_map do |child|
      next unless child.skin_tone.present?

      tone = child.skin_tone.downcase
      case tone
      when /éb[eè]ne|noir|très.?foncé|dark/
        # Négatif renforcé pour peau ébène : liste exhaustive des tons clairs à bloquer
        # FLUX tend à ignorer la peau foncée si le prompt contient des éléments "européens"
        "light skin, white skin, pale skin, fair skin, tan skin, tanned, caucasian, asian skin, light complexion, european features"
      when /brun.?foncé|foncé/
        # Peau brun foncé : bloque seulement les tons très clairs — pas aussi agressif qu'ébène
        "very pale skin, very light skin, fair skin, white skin"
      when /clair|blanc|fair|pale/
        "dark skin, black skin, brown skin, tanned skin"
      when /métis|mixed|doré|olive|mat/
        "very dark skin, very pale skin"
      end
    end.uniq

    # Base : artefacts visuels communs + hoodie non demandé (FLUX l'hallucine souvent)
    # On bloque aussi tout ce qui vieillit le héros : un enfant aux cheveux clairs
    # ne doit JAMAIS être rendu comme un adulte ou une personne âgée.
    negative = "blurry, low quality, deformed, ugly, bad anatomy, watermark, text, hoodie, sweatshirt, " \
               "elderly, old man, old woman, adult, grown-up, wrinkles, aged face, beard, mustache"

    # Négatifs spécifiques au style choisi
    # Pour watercolor : on bloque explicitement les styles anime/CGI qui dominent sinon
    chosen_style = @story.image_style.presence
    if chosen_style == "watercolor"
      negative += ", anime, manga, 3D render, CGI, Ghibli, cinematic, motion blur, " \
                  "photorealistic, digital painting sharp, neon, dark background, dramatic shadows"
    end

    negative += ", #{skin_negatives.join(', ')}" if skin_negatives.any?

    request.body = {
      prompt: prompt,
      negative_prompt: negative, # Bloque les peaux claires si le héros est à peau ébène
      image_size: "landscape_4_3", # Format paysage — idéal pour couverture de livre
      num_inference_steps: 28, # 28 = meilleure qualité (vs 24), acceptable pour FLUX Dev
      guidance_scale: 5.0, # 5.0 = plus fidèle aux contraintes (skin tone, accessoires)
      num_images: 1,
      enable_safety_checker: true
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
    client = OpenAI::Client.new(access_token: ENV.fetch("OPENAI_API_KEY", nil))

    # gpt-image-1 (modèle natif GPT-4o) — bien meilleur suivi de prompt que DALL-E 3 :
    # - Comprend les scènes complexes (mech + cockpit + personnage à l'intérieur)
    # - Filtre de contenu moins agressif que DALL-E 3 (pas de rejet 400 sur les aventures)
    # - Rendu cinématique plus détaillé
    # Pas de sanitisation nécessaire — gpt-image-1 gère le vocabulaire d'aventure enfantin
    response = client.images.generate(
      parameters: {
        prompt: prompt,
        model: "gpt-image-1",
        size: "1024x1024",
        quality: "medium", # "low" / "medium" / "high" — medium = bon équilibre qualité/coût
        n: 1
      }
    )

    # gpt-image-1 retourne l'image encodée en base64 (pas une URL)
    # DALL-E 3 retournait une URL — le format de réponse est différent
    b64 = response.dig("data", 0, "b64_json")
    return { success: false, error: "gpt-image-1 n'a pas retourné d'image" } unless b64

    # Décode le base64 et attache directement à ActiveStorage (pas besoin de télécharger)
    image_data = Base64.decode64(b64)
    @story.cover_image.attach(
      io: StringIO.new(image_data),
      filename: "histoire_#{@story.id}_couverture.png",
      content_type: "image/png"
    )

    Rails.logger.info("ImageGeneratorService — gpt-image-1 OK pour story ##{@story.id}")
    { success: true }
  rescue StandardError => e
    { success: false, error: "Erreur gpt-image-1 : #{e.message}" }
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
  # Construction du prompt image — approche "Portrait du héros"
  # ============================================================
  # OBJECTIF : l'enfant doit SE RECONNAÎTRE sur l'illustration pour s'identifier
  # au héros de son histoire du soir. On privilégie donc un PORTRAIT centré
  # (visage visible, expression douce) plutôt qu'une scène d'action où le
  # personnage est minuscule et méconnaissable.
  #
  # Le prompt est construit de façon DÉTERMINISTE en Ruby (pas d'appel IA
  # intermédiaire qui réécrit et perd des traits) :
  #   - héros : Child#image_description (âge + peau + cheveux + yeux + prénom)
  #   - décor : background_setting (thème de l'histoire, flou en arrière-plan)
  #   - style : STYLE_REFS selon image_style
  # Avantages : reproductible, testable, moins cher, pas de trait oublié.

  # ── Référence de style visuel selon le style choisi par le parent ──────────
  STYLE_REFS = {
    "ghibli" => "Makoto Shinkai and Studio Ghibli cinematic animation style, soft watercolor pastels, dreamy atmosphere",
    "comics" => "Spider-Man Into the Spider-Verse animation style, bold outlines, vibrant saturated colors",
    "pixar" => "Pixar and Disney 3D animation style, warm cinematic lighting, highly detailed CGI, expressive characters",
    "watercolor" => "vintage children's book illustration style, soft watercolor textures, warm hand-painted look, storybook fairy tale",
    # Cinématique : pas de référence dessin animé — gpt-image-1 choisit son rendu naturel
    "cinematic" => "cinematic movie concept art, photorealistic CGI, dramatic film poster style, epic blockbuster, child-safe"
  }.freeze

  def build_image_prompt
    # Héros : description physique précise en anglais (âge en tête → proportions
    # enfantines, puis peau/cheveux/yeux/prénom). image_description gère la
    # traduction sans ambiguïté (ex: cheveux "blanc" → "platinum white-blonde").
    heroes = @story.all_children.map(&:image_description).join(" and ")

    # Décor : monde de l'histoire, rendu doux et flou en arrière-plan (bokeh)
    setting = background_setting

    # Style visuel choisi par le parent (aquarelle par défaut — doux pour le coucher)
    style = STYLE_REFS[@story.image_style.presence || "watercolor"] || STYLE_REFS["watercolor"]

    # Composition PORTRAIT : enfant centré, visage net, buste visible, expression
    # heureuse et douce. Le décor reste flou pour ne pas voler la vedette au héros.
    composition = "Warm character portrait, the child centered in the frame, " \
                  "face clearly visible with a gentle happy expression, upper body shown, " \
                  "looking softly toward the viewer. Background: #{setting}, soft and blurred (bokeh). " \
                  "Warm golden bedtime lighting, cozy magical storybook atmosphere, child-safe."

    prompt = "A portrait of #{heroes}. #{composition} Art style: #{style}."

    # Garantie peau ébène : FLUX/gpt-image-1 ignorent souvent la peau très foncée.
    # On la réaffirme en TÊTE de prompt (premiers tokens = plus de poids).
    has_dark_skin = @story.all_children.any? { |c| c.skin_tone&.match?(/éb[eè]ne|noir|très.?foncé/i) }
    prompt = "BLACK CHILD WITH DARK EBONY SKIN as the main character. #{prompt}" if has_dark_skin

    # Suite d'épisode : on demande le même design de personnage que l'épisode précédent
    if @story.sequel? && @story.parent_story&.image_prompt.present?
      prompt += " Same character design and art style as the previous episode."
    end

    prompt
  end

  # ============================================================
  # Décor d'arrière-plan selon le thème de l'histoire
  # ============================================================
  # Retourne une courte description anglaise du monde de l'histoire, qui servira
  # d'arrière-plan FLOU derrière le portrait du héros. Un thème libre (custom_theme)
  # est utilisé tel quel ; sinon on mappe le world_theme vers un décor adapté.
  def background_setting
    return @story.custom_theme.to_s.strip if @story.custom_theme.present?

    {
      "space" => "a colorful cosmic space scene with stars, planets and a friendly rocket",
      "dinos" => "a lush prehistoric jungle with gentle dinosaurs and distant volcanoes",
      "princesses" => "an enchanted castle with flowering gardens and glowing towers",
      "pirates" => "a wooden pirate ship deck with the ocean and a golden sunset",
      "animals" => "a magical forest glade with friendly woodland animals"
    }.fetch(@story.world_theme.to_s, "a magical enchanted landscape")
  end

  # ============================================================
  # Téléchargement et attachement à ActiveStorage
  # ============================================================
  # Télécharge l'image depuis une URL distante et l'attache à l'histoire.
  # Utilisé par fal.ai et DALL-E (pas Pollinations qui bloque les requêtes serveur)
  def attach_image_from_url(url, extension = "png")
    # Sécurité : on vérifie que l'URL est bien HTTPS avant de l'ouvrir
    # URI.open peut lire des fichiers locaux si l'URL commence par file:// (SSRF)
    # Une URL malveillante retournée par une API compromise pourrait lire /etc/passwd
    unless url.to_s.start_with?("https://")
      raise ArgumentError,
            "URL invalide : seules les URLs HTTPS sont autorisées (reçu : #{url})"
    end

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
    # Si le téléchargement échoue, l'URL est déjà sauvegardée en base comme fallback
    Rails.logger.error("ImageGeneratorService — échec téléchargement : #{e.message}")
    raise # Re-raise pour que la méthode appelante capture l'erreur
  end
end
