# ============================================================
# Rack::Attack — protection contre le brute-force et l'abus
# ============================================================
# Ce fichier définit des règles de limitation de débit (rate limiting).
# Rack::Attack fonctionne comme un middleware Rack : il intercepte
# chaque requête AVANT qu'elle n'atteigne Rails, et la bloque si
# une règle est déclenchée.
#
# Règles configurées :
#   1. Brute-force connexion       → 10 tentatives / 20 secondes par IP
#   2. Brute-force mot de passe    → 5 tentatives / 20 secondes par IP
#   3. Spam inscription            → 5 inscriptions / heure par IP
#   4. Spam génération d'histoires → 10 créations / heure par IP
#   5. Spam waitlist               → 5 soumissions / heure par IP
#   6. Throttle global             → 300 requêtes / 5 minutes par IP
# ============================================================

class Rack::Attack

  # ──────────────────────────────────────────────────────────
  # SAFELIST — IP toujours autorisées (localhost en dev)
  # ──────────────────────────────────────────────────────────
  # En développement, on ne veut pas se bloquer soi-même.
  # req.ip retourne l'adresse IP du client.
  safelist("allow-localhost") do |req|
    req.ip == "127.0.0.1" || req.ip == "::1"
  end

  # ──────────────────────────────────────────────────────────
  # 1. Brute-force sur la page de connexion
  # ──────────────────────────────────────────────────────────
  # Quelqu'un qui essaie de deviner un mot de passe va envoyer
  # beaucoup de POST sur /users/sign_in en peu de temps.
  # On limite à 10 tentatives par IP toutes les 20 secondes.
  throttle("logins/ip", limit: 10, period: 20.seconds) do |req|
    # On cible uniquement le POST de connexion Devise
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  # ──────────────────────────────────────────────────────────
  # 2. Brute-force sur la réinitialisation de mot de passe
  # ──────────────────────────────────────────────────────────
  # Limite les demandes de reset password : 5 / 20s par IP
  throttle("password-reset/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/users/password" && req.post?
  end

  # ──────────────────────────────────────────────────────────
  # 3. Spam sur l'inscription
  # ──────────────────────────────────────────────────────────
  # On limite les créations de compte à 5 par heure par IP.
  # Évite la création en masse de faux comptes.
  throttle("signups/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.path == "/users" && req.post?
  end

  # ──────────────────────────────────────────────────────────
  # 4. Spam sur la génération d'histoires (endpoint coûteux)
  # ──────────────────────────────────────────────────────────
  # Chaque histoire génère un appel IA texte payant (Groq — Llama 3.3) et,
  # pour les comptes premium, une illustration payante (gpt-image-1).
  # On limite à 10 créations par heure par IP pour éviter un abus
  # qui ferait exploser la facture IA.
  throttle("stories/ip", limit: 10, period: 1.hour) do |req|
    req.ip if req.path == "/stories" && req.post?
  end

  # ──────────────────────────────────────────────────────────
  # 4 bis. Spam sur les autres routes de génération (replay/continue/retry/choose)
  # ──────────────────────────────────────────────────────────
  # POST /stories (ci-dessus) n'est PAS le seul endpoint qui lance un job IA.
  # Ces actions « membre » déclenchent elles aussi une génération payante :
  #   - replay   → recrée une histoire complète (texte + image)
  #   - continue → crée un nouvel épisode (texte + image)
  #   - retry    → relance une histoire échouée (texte + image)
  #   - choose   → lance la suite interactive (texte + image)
  # Sans throttle dédié, un script pourrait spammer /stories/:id/replay et faire
  # exploser la facture. On limite à 15 appels par heure par IP (un peu plus
  # large que la création directe car ces actions sont aussi des usages légitimes
  # répétés : refaire des choix, enchaîner des épisodes…).
  # La regex matche /stories/<id numérique>/<action> en POST uniquement.
  throttle("story-generate/ip", limit: 15, period: 1.hour) do |req|
    req.ip if req.post? && req.path.match?(%r{\A/stories/\d+/(replay|continue|retry|choose)\z})
  end

  # ──────────────────────────────────────────────────────────
  # 5. Spam sur les endpoints IA secondaires (audio + alternative)
  # ──────────────────────────────────────────────────────────
  # Ces deux endpoints appellent des APIs payantes (OpenAI TTS et Groq).
  # On les limite séparément de la création d'histoire car ils peuvent
  # être appelés plusieurs fois sur la même histoire.
  # audio : 20 appels / heure par IP (environ 1 audio toutes les 3min)
  # explore_alternative : 15 appels / heure par IP
  throttle("audio/ip", limit: 20, period: 1.hour) do |req|
    req.ip if req.path.end_with?("/audio") && req.post?
  end

  throttle("explore_alternative/ip", limit: 15, period: 1.hour) do |req|
    req.ip if req.path.end_with?("/explore_alternative") && req.post?
  end

  # ──────────────────────────────────────────────────────────
  # 6. Spam sur la liste d'attente
  # ──────────────────────────────────────────────────────────
  # Évite qu'un bot remplisse la waitlist avec de faux emails.
  throttle("waitlist/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.path == "/waitlist" && req.post?
  end

  # ──────────────────────────────────────────────────────────
  # 6. Throttle global — protection contre les attaques générales
  # ──────────────────────────────────────────────────────────
  # Une IP normale ne fait pas 300 requêtes en 5 minutes.
  # Ce filet de sécurité bloque les scrapers et attaques DDoS légères.
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    # On exclut les assets (images, CSS, JS) pour ne pas bloquer
    # un navigateur qui charge la page avec beaucoup de ressources.
    req.ip unless req.path.start_with?("/assets")
  end

  # ──────────────────────────────────────────────────────────
  # RÉPONSE EN CAS DE BLOCAGE
  # ──────────────────────────────────────────────────────────
  # Par défaut Rack::Attack renvoie un 429 vide.
  # On sert la page HTML public/429.html pour les navigateurs,
  # et du JSON pour les requêtes API (header Accept: application/json).
  # Le header Retry-After indique au client quand il peut réessayer.
  self.throttled_responder = lambda do |request|
    # Calcule le temps d'attente restant à partir des métadonnées du throttle
    retry_after = (request.env["rack.attack.match_data"] || {})[:period]

    # Si la requête attend du JSON (appels fetch() Stimulus par exemple),
    # on répond en JSON pour ne pas casser les handlers JS
    if request.env["HTTP_ACCEPT"]&.include?("application/json")
      [
        429,
        { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
        [{ error: "Trop de tentatives. Veuillez patienter avant de réessayer." }.to_json]
      ]
    else
      # Pour les requêtes HTML normales, on sert la belle page 429
      # File.read lit le fichier statique depuis public/ — pas besoin de Rails
      [
        429,
        { "Content-Type" => "text/html; charset=utf-8", "Retry-After" => retry_after.to_s },
        [File.read(Rails.root.join("public", "429.html"))]
      ]
    end
  end
end
