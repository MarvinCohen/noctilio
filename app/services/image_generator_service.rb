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
  # Mots-clés d'action pour identifier la scène la plus épique
  # Défini au niveau classe (pas dans une méthode) — requis par Ruby
  # ----------------------------------------------------------------
  ACTION_KEYWORDS = %w[
    bondit frappe combat affronte attaque charge plonge s'élance surgit
    jaillit fend tranche transperce explose éclate rugit hurle tonne
    fonce tourbillonne s'envole bataille affrontement éclair flamme
    tempête choc impact lame épée coup poursuite fuir sauter courir
    vaincre terrasse renverse déchire saisit arrache défend protège
  ].freeze

  # ----------------------------------------------------------------
  # Style visuel cohérent pour toutes les illustrations de l'app
  # Optimisé pour FLUX.1 Dev — langage naturel narratif (pas de liste de mots-clés)
  # Structure FLUX : sujet → action → environnement → lumière → style/mood
  #
  # Style : anime semi-réaliste — inspiré des productions Makoto Shinkai (Your Name,
  # Weathering With You) et des films Ghibli récents. Personnages expressifs avec
  # proportions réalistes (pas super-déformés), décors ultra-détaillés, lumière
  # atmosphérique et couleurs vibrantes.
  # ----------------------------------------------------------------
  VISUAL_STYLE = "semi-realistic anime illustration, " \
                 "Makoto Shinkai and Studio Ghibli cinematic style, " \
                 "expressive characters with realistic proportions, " \
                 "highly detailed painterly backgrounds, " \
                 "dramatic volumetric lighting with god rays, " \
                 "vibrant saturated colors with deep shadows, " \
                 "cinematic widescreen composition, " \
                 "child-safe, no violence, magical and emotional atmosphere"

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
      num_inference_steps: 24,               # 24 = meilleur compromis qualité/vitesse pour FLUX Dev
      guidance_scale:      4.0,              # 4.0 = créatif mais fidèle (recommandé FLUX illustrations)
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
  # Construction du prompt image — optimisé FLUX.1 Dev
  # ============================================================
  # FLUX fonctionne en langage naturel narratif, pas en liste de mots-clés.
  # Structure optimale : sujet+action → environnement → lumière → style → mood
  # Longueur idéale : 40-60 mots (assez précis sans noyer le modèle)
  def build_image_prompt
    # Extrait la scène clé du climax de l'histoire (2/3 du texte)
    key_moment = extract_key_moment

    # Description physique précise de chaque héros pour la cohérence visuelle
    # FLUX intègre bien les caractéristiques physiques (lunettes, couleur des cheveux, etc.)
    hero_parts = @story.all_children.map do |child|
      desc = "#{child.name} (#{child.age} years old"
      desc += ", #{child.child_description}" if child.child_description.present?
      desc += ")"
      desc
    end
    heroes_str = hero_parts.join(" and ")

    # Construit le prompt en langage naturel narratif — optimisé FLUX
    # Priorité : custom_theme (thème de l'aventure) > scène extraite > fallback générique
    # Le custom_theme donne l'univers visuel exact voulu par le parent
    adventure_context = if @story.custom_theme.present?
      # Utilise le thème de l'aventure défini par le parent — donne l'univers visuel exact
      @story.custom_theme.truncate(100)
    elsif key_moment.present?
      # Utilise la scène extraite du texte comme contexte visuel
      key_moment.truncate(100)
    else
      "an epic magical adventure"
    end

    # Prompt final : scène d'action épique → héros → style → lumière
    # "action scene", "dynamic pose", "motion blur" ancrent l'image dans le mouvement
    prompt = "epic action scene, #{adventure_context}, " \
             "#{heroes_str} as the main characters in dynamic combat or heroic pose, " \
             "intense motion and energy, characters in the heat of the action, " \
             "anime-style character design with detailed expressive faces, " \
             "#{VISUAL_STYLE}, " \
             "dramatic rim light, motion blur on fast movements, " \
             "all characters visible together in one explosive scene"

    # Si c'est un épisode de suite, on impose la continuité visuelle avec l'épisode précédent.
    # On extrait les éléments clés du prompt parent (style, couleurs, description des personnages)
    # et on les ajoute explicitement pour ancrer le modèle sur le même character design.
    if @story.sequel? && @story.parent_story&.image_prompt.present?
      parent_prompt = @story.parent_story.image_prompt

      # On prend les 300 premiers caractères du prompt parent — la description des personnages
      # et le style visuel sont toujours au début, après "epic action scene"
      parent_style_ref = parent_prompt.truncate(300)

      prompt += ", SAME CHARACTER DESIGN AND ART STYLE AS: #{parent_style_ref}, " \
                "exact same character appearances, same color palette, same art style, " \
                "visual consistency with previous episode, same face designs"
    end

    prompt
  end

  # Extrait le moment le plus épique/action de l'histoire pour l'illustration
  #
  # Stratégie :
  #   1. Cherche le paragraphe avec le plus de mots d'action (combat, éclair, bondit...)
  #   2. Si aucun trouvé : fallback sur le paragraphe aux 2/3 (zone climax habituelle)
  #
  # Les mots d'action sont des indicateurs forts d'une scène visuelle intense —
  # exactement ce qu'on veut pour une illustration épique.
  def extract_key_moment
    return "" if @story.content.blank?

    # Nettoie le contenu : retire les blocs [CHOIX] et les titres markdown
    # NOTE : on utilise [#]{1,3} au lieu de #{1,3} pour éviter l'interpolation Ruby
    clean = @story.content
                  .gsub(/\[CHOIX\].*?\[FIN CHOIX\]/m, "")
                  .gsub(/^[#]{1,3} .+$/, "")
                  .strip

    # Récupère tous les paragraphes non vides d'au moins 80 caractères
    # (les courts sont souvent des transitions, pas des scènes visuelles)
    paragraphs = clean.split(/\n\n+/).map(&:strip).reject { |p| p.length < 80 }
    return "" if paragraphs.empty?

    # Score chaque paragraphe selon le nombre de mots d'action qu'il contient
    best_paragraph = paragraphs.max_by do |para|
      para_downcase = para.downcase
      ACTION_KEYWORDS.count { |word| para_downcase.include?(word) }
    end

    # Vérifie que le "meilleur" paragraphe a au moins 1 mot d'action
    # Sinon, fallback sur le paragraphe aux 2/3 du texte
    best_score = ACTION_KEYWORDS.count { |w| best_paragraph.downcase.include?(w) }
    if best_score == 0
      climax_index  = (paragraphs.length * 2 / 3).clamp(0, paragraphs.length - 1)
      best_paragraph = paragraphs[climax_index]
    end

    moment = best_paragraph.gsub(/\n/, " ").strip

    # Limite à 200 caractères pour ne pas dépasser la longueur optimale du prompt image
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
