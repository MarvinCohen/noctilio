source "https://rubygems.org"

# Version Ruby explicite — nécessaire pour Heroku
ruby "3.3.5"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

gem "sprockets-rails"
gem "bootstrap", "~> 5.3"
gem "devise", "~> 5.0"
# Connexion via Google OAuth2 — permet aux utilisateurs de s'inscrire/connecter avec leur compte Google
gem "omniauth-google-oauth2", "~> 1.1"
# Protection CSRF pour OmniAuth — obligatoire avec Rails (bloque les attaques de type CSRF sur le callback OAuth)
gem "omniauth-rails_csrf_protection", "~> 1.0"
# Traductions françaises pour les helpers Rails (time_ago_in_words, etc.)
gem "rails-i18n", "~> 8.0"
# Convertit le markdown (généré par l'IA) en HTML propre côté serveur
# Plus fiable que parser le markdown manuellement en JavaScript
gem "redcarpet", "~> 3.6"
gem "autoprefixer-rails", "~> 10.4"
gem "font-awesome-sass", "~> 6.1"
# Version officielle Rubygems — plus stable que le HEAD GitHub
gem "simple_form", "~> 5.4"
gem "sassc-rails"

# Intelligence artificielle — génération d'histoires et d'images
gem "ruby-openai", "~> 7.0"

# Stockage cloud des images générées (ActiveStorage)
# Nécessaire sur Heroku car le filesystem est éphémère
gem "cloudinary", "~> 1.29"
gem "activestorage-cloudinary-service"

# Abonnements Stripe — gère les paiements et plans premium
gem "pay", "~> 7.0"
gem "stripe", "~> 12.0"

# Protection contre le brute-force et l'abus de requêtes
# Bloque les IP qui spamment la connexion ou les endpoints coûteux (OpenAI)
gem "rack-attack", "~> 6.8"

# Monitoring des erreurs en production — capture les exceptions et les remonte
# sur le tableau de bord Sentry pour être alerté des bugs réels des utilisateurs.
# sentry-ruby = client de base ; sentry-rails = intégration Rails (jobs, requêtes).
# Reste un no-op tant que la variable d'env SENTRY_DSN n'est pas définie
# (voir config/initializers/sentry.rb) → aucun impact en dev/test.
gem "sentry-ruby"
gem "sentry-rails"

# Génération de PDF 100% Ruby (aucun binaire système à installer, contrairement
# à wkhtmltopdf) — sert à exporter une histoire en PDF téléchargeable pour que
# les parents puissent archiver/imprimer les histoires. Voir StoryPdfService.
gem "prawn", "~> 2.5"

# Notifications push web (PWA) — envoi de rappels "histoire du soir" via le
# Web Push Protocol (chiffré, authentifié par une paire de clés VAPID).
# Clés à fournir en ENV : VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY
# Génération des clés : bundle exec rails runner "require 'web-push'; pp WebPush.generate_key"
gem "web-push", "~> 3.0"

group :development, :test do
  gem "dotenv-rails"
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # Détecte les requêtes N+1 et les eager loadings inutiles pendant le développement.
  # Affiche une alerte (log + bandeau navigateur) dès qu'une vue déclenche une
  # requête par enregistrement au lieu d'un `includes` → aide à corriger les perfs tôt.
  gem "bullet"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end

gem "omniauth", "~> 2.1"
