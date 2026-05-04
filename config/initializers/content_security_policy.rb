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

    # Scripts : uniquement depuis ce domaine + nonce pour les scripts inline de Rails/Turbo
    policy.script_src :self

    # Styles : ce domaine + Google Fonts + unsafe_inline nécessaire pour Bootstrap 5
    # Bootstrap 5 injecte des styles inline — impossible à supprimer sans réécrire Bootstrap
    policy.style_src :self, "https://fonts.googleapis.com", :unsafe_inline

    # Polices : ce domaine + Google Fonts (gstatic = où les fichiers .woff2 sont hébergés)
    policy.font_src :self, "https://fonts.gstatic.com", :data

    # Images : ce domaine + HTTPS (Cloudinary, fal.ai CDN, DALL-E) + data: (base64)
    # On autorise tout HTTPS car les URLs Cloudinary et fal.ai peuvent varier
    policy.img_src :self, :https, :data

    # Requêtes fetch() / XHR : uniquement vers ce domaine (appels Stimulus → Rails)
    policy.connect_src :self

    # Désactiver complètement les plugins Flash/Java (obsolètes et dangereux)
    policy.object_src :none

    # Interdire l'intégration de l'app dans une iframe sur un autre site (anti-clickjacking)
    policy.frame_ancestors :none
  end

  # Génère un nonce unique par requête pour les scripts inline autorisés
  # Le nonce est un token aléatoire que Rails injecte dans les balises <script> légitimes
  # Si un script n'a pas ce nonce, le navigateur le bloque
  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }

  # Applique le nonce uniquement aux scripts (les styles utilisent :unsafe_inline à cause de Bootstrap)
  config.content_security_policy_nonce_directives = %w[script-src]
end
