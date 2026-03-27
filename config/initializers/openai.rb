# ============================================================
# Configuration du client OpenAI
# ============================================================
# Ce fichier configure la gem ruby-openai avec notre clé API.
# La clé doit être définie dans le fichier .env :
#   OPENAI_API_KEY=sk-...votre-clé...
#
# NE JAMAIS mettre la clé directement dans ce fichier !
# NE JAMAIS committer le fichier .env (il est dans .gitignore)

OpenAI.configure do |config|
  # Clé API chargée depuis la variable d'environnement
  config.access_token = ENV.fetch("OPENAI_API_KEY", nil)

  # Timeout de 120 secondes — la génération d'histoire peut être longue
  config.request_timeout = 120
end
