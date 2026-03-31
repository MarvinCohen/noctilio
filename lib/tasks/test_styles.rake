# ============================================================
# Tâche Rake — test des styles d'illustration fal.ai
# ============================================================
# Génère 6 images avec des styles différents via fal.ai (FLUX Dev)
# et affiche les URLs dans le terminal.
#
# Usage :
#   rails test:styles
#
# Prérequis : FAL_API_KEY doit être configurée dans .env

namespace :test do
  desc "Génère 6 images de styles différents via fal.ai et affiche les URLs"
  task styles: :environment do
    require "net/http"
    require "json"

    # Scène de base identique pour tous les styles — permet une vraie comparaison
    base_scene = "a child named Leo, 6 years old, exploring a magical forest with glowing fireflies"

    # Les 15 styles à tester — chaque style est un préfixe ajouté avant la scène
    styles = {
      "1. Aquarelle (style actuel)" =>
        "children book illustration, soft watercolor, pastel colors, hand-drawn style, warm magical atmosphere, safe for kids",

      "2. Pixar / 3D animé" =>
        "3D animated Pixar style, vibrant colors, expressive characters, cinematic lighting, safe for kids",

      "3. Manga / BD japonaise" =>
        "manga style, clean ink lines, expressive eyes, japanese comic style, colorful, safe for kids",

      "4. Flat Design / Vectoriel" =>
        "flat design illustration, bold colors, geometric shapes, minimal modern vector art, safe for kids",

      "5. Vintage / Livre ancien" =>
        "vintage storybook illustration, retro style, warm earthy tones, textured paper feel, old book, safe for kids",

      "6. Conte de fées / Magique" =>
        "fairy tale illustration, glowing magical light, enchanted forest atmosphere, dreamy soft colors, safe for kids",

      "7. Studio Ghibli" =>
        "Studio Ghibli anime style, soft colors, detailed backgrounds, magical atmosphere, Hayao Miyazaki inspired, safe for kids",

      "8. Cartoon / Disney" =>
        "Disney cartoon style, bright colors, expressive faces, clean lines, animated movie style, safe for kids",

      "9. Aquarelle sombre" =>
        "dark watercolor illustration, moody atmosphere, deep blues and purples, mysterious forest, dramatic lighting, safe for kids",

      "10. Crayon / Dessin enfant" =>
        "crayon drawing style, childlike art, colorful, naive illustration, hand-drawn by a child, playful and innocent",

      "11. Low poly / Géométrique" =>
        "low poly 3D art style, geometric shapes, colorful triangles, modern minimalist, faceted surfaces",

      "12. Peinture à l'huile" =>
        "oil painting style, rich textures, impressionist, warm golden light, classic art, museum quality, safe for kids",

      "13. Pixel art" =>
        "pixel art style, retro 16-bit, colorful sprites, video game aesthetic, cute characters, safe for kids",

      "14. Pop art" =>
        "pop art style, bold outlines, bright saturated colors, Andy Warhol inspired, comic book dots, safe for kids",

      "15. Illustration scandinave" =>
        "Scandinavian folk art style, geometric patterns, muted nordic colors, hygge atmosphere, minimalist, safe for kids"
    }

    puts "\n🌙 Noctilio — Test des styles fal.ai"
    puts "=" * 60
    puts "Scène : #{base_scene}"
    puts "=" * 60

    styles.each do |name, style_prompt|
      puts "\n#{name}"
      print "  Génération en cours..."

      # Construction du prompt complet : style + scène
      full_prompt = "#{style_prompt}. #{base_scene}."

      # Appel à l'API fal.ai — même configuration que ImageGeneratorService
      uri  = URI("https://fal.run/fal-ai/flux/dev")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = true
      http.read_timeout = 120
      http.open_timeout = 10

      request = Net::HTTP::Post.new(uri.path)
      request["Authorization"] = "Key #{ENV['FAL_API_KEY']}"
      request["Content-Type"]  = "application/json"
      request.body = {
        prompt:                full_prompt,
        image_size:            "landscape_4_3",
        num_inference_steps:   28,
        guidance_scale:        3.5,
        num_images:            1,
        enable_safety_checker: true
      }.to_json

      begin
        response = http.request(request)
        body     = JSON.parse(response.body)

        if response.code == "200" && body["images"]&.first&.dig("url")
          # Succès — affiche l'URL de l'image générée
          url = body["images"].first["url"]
          puts " ✓"
          puts "  URL : #{url}"
        else
          # Erreur API — affiche le message d'erreur
          error = body["detail"] || body["error"] || "Erreur #{response.code}"
          puts " ✗"
          puts "  Erreur : #{error}"
        end
      rescue StandardError => e
        puts " ✗"
        puts "  Exception : #{e.message}"
      end
    end

    puts "\n" + "=" * 60
    puts "✓ Terminé — copie une URL dans ton navigateur pour voir l'image"
    puts "=" * 60
  end
end
