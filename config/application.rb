require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Noctilio
  class Application < Rails::Application
    config.generators do |generate|
      generate.assets false
      generate.helper false
      generate.test_framework :test_unit, fixture: false
    end
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Langue par défaut de l'application — active les traductions FR pour Devise et les messages Rails
    config.i18n.default_locale = :fr

    # Liste des langues disponibles dans l'app (multilingue).
    # I18n.locale ne pourra prendre QUE l'une de ces valeurs — toute autre est refusée.
    # fr = défaut, puis en/es/de/it/pt. On y ajoute des langues simplement en complétant
    # cette liste et en créant le fichier config/locales/<langue>.yml correspondant.
    config.i18n.available_locales = [:fr, :en, :es, :de, :it, :pt]

    # Fallback : si une clé de traduction manque dans la langue courante, on retombe
    # automatiquement sur le français (la langue source) au lieu d'afficher une erreur
    # "translation missing". Indispensable pendant la traduction progressive des vues.
    config.i18n.fallbacks = [:fr]

    # Active Rack::Attack comme middleware de protection contre le brute-force
    # Il doit être inséré tôt dans la pile pour intercepter les requêtes avant Rails
    config.middleware.use Rack::Attack

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
