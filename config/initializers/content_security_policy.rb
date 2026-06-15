# Redémarre le serveur après modification de ce fichier.
#
# La CSP (Content Security Policy) est un en-tête HTTP qui dit au navigateur
# quelles sources sont autorisées à charger des ressources (scripts, styles, images...).
# C'est la principale défense contre les attaques XSS.
#
# Pourquoi c'est important pour Noctilio :
# L'app génère du contenu depuis une IA externe (Groq/Llama). Si une réponse
# malformée contenait du HTML/JS malveillant, la CSP empêche le navigateur de l'exécuter.

Rails.application.configure do
  config.content_security_policy do |policy|
    # Par défaut : n'autoriser que les ressources venant du même domaine
    policy.default_src :self

    # Scripts : ce domaine + nonce pour les scripts inline de Rails/Turbo
    # + cloud.umami.is : d'où est servi le script d'analytics Umami (analytics cookieless)
    policy.script_src :self, "https://cloud.umami.is"

    # Styles : ce domaine + Google Fonts + unsafe_inline nécessaire pour Bootstrap 5
    # Bootstrap 5 injecte des styles inline — impossible à supprimer sans réécrire Bootstrap
    policy.style_src :self, "https://fonts.googleapis.com", :unsafe_inline

    # Polices : ce domaine + Google Fonts (gstatic = où les fichiers .woff2 sont hébergés)
    policy.font_src :self, "https://fonts.gstatic.com", :data

    # Images : ce domaine + HTTPS (Cloudinary, fal.ai CDN, DALL-E) + data: (base64)
    # On autorise tout HTTPS car les URLs Cloudinary et fal.ai peuvent varier
    policy.img_src :self, :https, :data

    # Requêtes fetch() / XHR : ce domaine (appels Stimulus → Rails)
    # + cloud.umami.is : domaine d'où le script Umami est chargé
    # + gateway.umami.is : domaine RÉEL vers lequel Umami envoie les events (POST /api/send)
    #   Vérifié en prod via l'onglet Réseau : le script est servi par cloud.umami.is
    #   mais le beacon de tracking part vers gateway.umami.is (les deux sont donc nécessaires)
    policy.connect_src :self, "https://cloud.umami.is", "https://gateway.umami.is"

    # Désactiver complètement les plugins Flash/Java (obsolètes et dangereux)
    policy.object_src :none

    # Interdire l'intégration de l'app dans une iframe sur un autre site (anti-clickjacking)
    policy.frame_ancestors :none
  end

  # Génère le nonce pour les scripts inline autorisés.
  # Le nonce est un token que Rails injecte dans les balises <script> légitimes ;
  # si un script n'a pas ce nonce, le navigateur le bloque.
  #
  # IMPORTANT — pourquoi le nonce est lié à la SESSION (et pas purement aléatoire) :
  # Turbo (Hotwire) navigue sans recharger la page : il récupère la nouvelle page
  # en fetch() puis remplace le <body>. Or le navigateur continue d'imposer la CSP
  # du tout PREMIER chargement (avec son nonce d'origine). Si on régénère un nonce
  # aléatoire à chaque requête, le <body> ré-injecté par Turbo porte un nouveau nonce
  # qui ne correspond plus à celui imposé par le document → les scripts inline
  # (révélation du dashboard, étoiles…) sont bloqués et la page paraît "vide".
  #
  # Solution : un nonce STABLE par session. Pour un utilisateur connecté, session.id
  # existe et reste constant entre deux navigations Turbo → le nonce correspond
  # toujours → plus de blocage.
  #
  # Repli SecureRandom : un visiteur anonyme peut ne pas avoir de session.id encore
  # créé (ex : tout premier arrivage sur la landing). Dans ce cas session.id est vide,
  # ce qui donnerait un nonce "" qui bloquerait TOUS les scripts inline. On retombe
  # donc sur SecureRandom pour garantir un nonce non-vide dans ce cas-là.
  config.content_security_policy_nonce_generator = ->(request) do
    request.session.id.to_s.presence || SecureRandom.base64(16)
  end

  # Applique le nonce uniquement aux scripts (les styles utilisent :unsafe_inline à cause de Bootstrap)
  config.content_security_policy_nonce_directives = %w[script-src]
end
