# ============================================================
# Tâches Rake — maintenance des couvertures d'histoires
# ============================================================
# Contexte : certaines histoires ont une cover_image ATTACHÉE en base
# (active_storage_attachments + blob) dont le FICHIER n'existe pas/plus sur
# Cloudinary. ActiveStorage régénère alors une URL valide vers un objet
# inexistant → erreurs 404 répétées dans la console à chaque chargement de page.
#
# Deux tâches :
#   covers:audit         → LISTE les couvertures cassées (HEAD 404). Lecture seule.
#   covers:purge_broken  → PURGE ces attachements orphelins (la carte retombe
#                          alors proprement sur le placeholder ✨, plus de 404).
#
# Usage :
#   bin/rails covers:audit
#   bin/rails covers:purge_broken
#
# Conseil : toujours lancer covers:audit d'abord pour vérifier la liste,
# puis covers:purge_broken une fois la liste confirmée.

namespace :covers do
  # ----------------------------------------------------------
  # Vérifie l'existence réelle du fichier de couverture sur le service de
  # stockage (Cloudinary en prod) via une requête HEAD.
  # Retourne true si le fichier RÉPOND (200/30x), false si 404 ou erreur réseau.
  # ----------------------------------------------------------
  def cover_reachable?(story)
    require "net/http"

    # url = URL publique servie par le service de stockage (Cloudinary).
    # C'est EXACTEMENT l'URL qui apparaît en 404 dans la console.
    url = story.cover_image.url
    uri = URI.parse(url)

    # Requête HEAD : on ne télécharge pas l'image, on veut juste le code HTTP.
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = 5
    http.read_timeout = 5

    response = http.request_head(uri.request_uri)
    # 2xx ou 3xx = fichier présent ; tout le reste (404…) = cassé.
    response.code.to_i < 400
  rescue StandardError => e
    # Erreur réseau / URL invalide : on considère la couverture comme injoignable.
    Rails.logger.warn("covers — HEAD échoué pour story ##{story.id} : #{e.message}")
    false
  end

  # ----------------------------------------------------------
  # covers:audit — LISTE les couvertures cassées (ne modifie RIEN).
  # ----------------------------------------------------------
  desc "Liste les histoires dont la couverture renvoie 404 (lecture seule)"
  task audit: :environment do
    # On ne teste que les histoires qui ont réellement un attachement cover_image
    # (les autres n'ont pas d'URL Cloudinary, donc pas de 404 possible).
    stories = Story.joins(:cover_image_attachment).distinct

    puts "Audit des couvertures — #{stories.count} histoire(s) avec une cover_image attachée."

    broken = [] # accumulateur des histoires cassées (pour le récapitulatif)

    stories.find_each do |story|
      if cover_reachable?(story)
        # Couverture OK : rien à signaler.
        next
      else
        # Couverture cassée : on l'ajoute à la liste et on l'affiche.
        broken << story
        puts "  ✗ CASSÉE — story ##{story.id} — #{story.title.inspect}"
      end
    end

    puts "—" * 50
    if broken.empty?
      puts "Aucune couverture cassée. Rien à purger."
    else
      puts "#{broken.size} couverture(s) cassée(s) détectée(s)."
      puts "Pour les purger : bin/rails covers:purge_broken"
    end
  end

  # ----------------------------------------------------------
  # covers:purge_broken — PURGE les couvertures orphelines (HEAD 404).
  # La purge supprime l'attachement + le blob : la carte affichera ensuite
  # proprement le placeholder ✨ (plus de requête 404).
  # ----------------------------------------------------------
  desc "Purge les couvertures orphelines (fichier Cloudinary absent / 404)"
  task purge_broken: :environment do
    stories = Story.joins(:cover_image_attachment).distinct

    puts "Purge des couvertures cassées — #{stories.count} histoire(s) à vérifier."

    purged = 0 # compteur de purges effectuées

    stories.find_each do |story|
      # On ne purge QUE si le fichier est réellement injoignable (404).
      next if cover_reachable?(story)

      # purge : supprime l'attachement ET le blob associé (synchrone).
      story.cover_image.purge
      purged += 1
      puts "  ✓ purgée — story ##{story.id} — #{story.title.inspect}"
    end

    puts "—" * 50
    puts "#{purged} couverture(s) orpheline(s) purgée(s)."
  end
end
