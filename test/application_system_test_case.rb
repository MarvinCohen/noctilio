# Classe de base pour les tests système (Capybara + Chrome headless)
# Tous les tests dans test/system/ héritent de cette classe.
require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Utilise Chrome en mode headless (sans interface graphique) pour les tests CI
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]
end
