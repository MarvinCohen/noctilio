# Procfile — dit à Heroku quels processus lancer
#
# web    : le serveur Rails (Puma) — obligatoire
# worker : Solid Queue pour les jobs background (génération d'histoires)
#          Sans ce processus, les histoires ne seront jamais générées.

web: bundle exec puma -C config/puma.rb
worker: bundle exec rails solid_queue:start
