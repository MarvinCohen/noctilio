# ============================================================
# Rake task — génération des images d'exemple de styles
# ============================================================
# Génère 4 images via fal.ai (FLUX.1 Dev) montrant un même enfant
# décliné dans chacun des 4 styles visuels disponibles dans l'app.
#
# Ces images sont sauvegardées comme assets statiques dans :
#   public/images/style_examples/{style}.jpg
#
# Elles sont ensuite affichées dans le formulaire de création
# d'histoire (étape "Choix du style") pour aider l'utilisateur
# à visualiser chaque style avant de choisir.
#
# Usage :
#   rails styles:generate_examples
#
# Prérequis :
#   FAL_API_KEY doit être configurée dans .env

namespace :styles do
  desc "Génère les 4 images d'exemple de styles via fal.ai → public/images/style_examples/"
  task generate_examples: :environment do
    require "net/http"
    require "json"
    require "open-uri"
    require "fileutils"

    # Vérification de la clé API avant de commencer
    unless ENV["FAL_API_KEY"].present?
      puts "Erreur : FAL_API_KEY manquante dans .env"
      exit 1
    end

    # Crée le dossier de destination s'il n'existe pas
    output_dir = Rails.root.join("public", "images", "style_examples")
    FileUtils.mkdir_p(output_dir)
    puts "Dossier de sortie : #{output_dir}"

    # ── Personnages de référence ─────────────────────────────────────────────
    # Même scène dans les 4 styles, déclinée en version fille et garçon
    # pour afficher la bonne série selon le genre de l'enfant sélectionné
    girl_character = "a 7-year-old girl with brown hair tied in two small braids, bright green eyes, " \
                     "fair skin, wearing a simple colorful outfit"

    boy_character  = "a 7-year-old boy with short brown hair, bright blue eyes, " \
                     "fair skin, wearing a simple colorful outfit"

    # ── Prompts par style ────────────────────────────────────────────────────
    # Chaque style a une version fille (suffix _girl) et une version garçon (suffix _boy)
    # La scène est identique pour que la comparaison soit visuelle et non narrative
    styles = {
      "ghibli" => {
        name: "Ghibli",
        scene: "running joyfully through a magical glowing forest at golden hour, " \
               "fireflies surrounding the child, soft wind, wonder on the face, " \
               "tall ancient trees with glowing leaves in the background. " \
               "Makoto Shinkai and Studio Ghibli cinematic animation style, " \
               "soft watercolor pastels, dreamy atmosphere, lush hand-painted backgrounds, " \
               "emotional warm golden lighting, vibrant colors, cinematic widescreen composition, " \
               "child-safe, magical and emotional"
      },
      "comics" => {
        name: "Comics",
        scene: "leaping heroically between rooftops at sunset with a big confident smile, " \
               "dynamic action pose, colorful cape flowing, city skyline silhouette behind, " \
               "energy lines radiating from the movement. " \
               "Spider-Man Into the Spider-Verse animation style, " \
               "bold black outlines, vibrant highly saturated colors, halftone dot patterns, " \
               "dynamic graphic composition, motion blur, strong contrast, " \
               "child-safe, comic book energy, action-packed"
      },
      "pixar" => {
        name: "Pixar",
        scene: "discovering a glowing magical treasure chest in an enchanted cave, " \
               "eyes wide with wonder and excitement, golden magical light illuminating the face, " \
               "colorful crystals and glowing mushrooms surrounding. " \
               "Pixar and Disney 3D animation style, " \
               "warm cinematic volumetric lighting, highly detailed CGI render, " \
               "expressive face with big eyes, subsurface skin scattering, " \
               "rich vibrant colors, dramatic composition, child-safe, magical atmosphere"
      },
      "watercolor" => {
        name: "Aquarelle",
        scene: "walking gently through an enchanted autumn forest, " \
               "colorful leaves falling softly, a small curious fox companion trotting beside, " \
               "gentle dreamy expression, warm afternoon light filtering through the trees. " \
               "Vintage children's book illustration style, " \
               "soft watercolor textures, warm hand-painted brushstrokes, " \
               "storybook fairy tale aesthetic, warm ochre and rose color palette, " \
               "delicate ink outlines, dreamy and gentle, child-safe"
      }
    }

    # ── Génération des deux séries ───────────────────────────────────────────
    # Série fille (_girl) et série garçon (_boy)
    series = {
      "girl" => girl_character,
      "boy"  => boy_character
    }

    series.each do |gender, character|
      puts "\n=== Serie #{gender.upcase} ==="

      styles.each do |key, config|
        # Détermine le nom du fichier de sortie : ex. ghibli_girl.jpg
        output_path = output_dir.join("#{key}_#{gender}.jpg")

        # Saute si l'image existe déjà (évite de regénérer inutilement)
        if File.exist?(output_path)
          puts "  [#{config[:name]}] Deja existante, ignoree."
          next
        end

        puts "\n  Generation #{config[:name]} (#{gender})..."

        begin
          # Requête HTTP vers fal.ai FLUX.1 Dev
          uri  = URI("https://fal.run/fal-ai/flux/dev")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl      = true
          http.read_timeout = 120
          http.open_timeout = 10

          request = Net::HTTP::Post.new(uri.path)
          request["Authorization"] = "Key #{ENV['FAL_API_KEY']}"
          request["Content-Type"]  = "application/json"

          # Combine le personnage et la scène pour former le prompt complet
          prompt = "#{character}, #{config[:scene]}"

          request.body = {
            prompt:          prompt,
            negative_prompt: "blurry, low quality, deformed, ugly, bad anatomy, watermark, text, adult content, violence",
            image_size:          "landscape_4_3",
            num_inference_steps: 28,
            guidance_scale:      4.5,
            num_images:          1,
            enable_safety_checker: true
          }.to_json

          response = http.request(request)
          body     = JSON.parse(response.body)

          unless response.code == "200" && body["images"]&.first&.dig("url")
            error = body["detail"] || body["error"] || "Code HTTP #{response.code}"
            puts "  Erreur fal.ai : #{error}"
            next
          end

          image_url = body["images"].first["url"]
          puts "  Image generee : #{image_url}"

          URI.open(image_url, read_timeout: 60) do |img|
            File.binwrite(output_path, img.read)
          end
          puts "  Sauvegardee dans #{output_path}"

        rescue StandardError => e
          puts "  Erreur : #{e.message}"
        end
      end
    end

    puts "\nTermine ! Images disponibles dans public/images/style_examples/"
  end
end
