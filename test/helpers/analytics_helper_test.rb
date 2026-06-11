# Test du AnalyticsHelper
# Vérifie la logique d'activation du script de tracking Umami :
# - désactivé si la variable d'env UMAMI_WEBSITE_ID est absente (cas dev/test)
# - actif pour un visiteur anonyme ou un utilisateur non-admin quand l'env est défini
# - désactivé pour un admin (le mode test ne doit pas polluer les statistiques)
require "test_helper"

class AnalyticsHelperTest < ActionView::TestCase
  # current_user : redéfini ici pour simuler la session Devise dans les tests.
  # Grâce à attr_accessor, respond_to?(:current_user) devient true dans le helper,
  # ce qui permet de tester l'exclusion des comptes admin.
  attr_accessor :current_user

  # Sauvegarde la valeur d'origine de l'env avant chaque test
  setup do
    @original_umami_id = ENV["UMAMI_WEBSITE_ID"]
  end

  # Restaure l'env après chaque test pour éviter toute fuite entre les tests
  teardown do
    if @original_umami_id.nil?
      ENV.delete("UMAMI_WEBSITE_ID")
    else
      ENV["UMAMI_WEBSITE_ID"] = @original_umami_id
    end
  end

  # Sans la variable d'env (cas dev/test), l'analytics doit être désactivé
  # Pourquoi : on ne veut jamais tracker en local ni dans la suite de tests
  test "umami_enabled? est faux si UMAMI_WEBSITE_ID est absent" do
    # Arrange
    ENV.delete("UMAMI_WEBSITE_ID")
    self.current_user = nil

    # Assert
    assert_not umami_enabled?,
               "L'analytics ne doit pas être actif sans UMAMI_WEBSITE_ID"
  end

  # Avec la variable d'env et un visiteur anonyme, l'analytics est actif
  # Pourquoi : c'est le cas nominal sur la landing page publique
  test "umami_enabled? est vrai si UMAMI_WEBSITE_ID présent et visiteur anonyme" do
    # Arrange
    ENV["UMAMI_WEBSITE_ID"] = "test-website-id"
    self.current_user = nil

    # Assert
    assert umami_enabled?,
           "L'analytics doit être actif pour un visiteur anonyme en prod"
  end

  # Avec la variable d'env mais un admin connecté, l'analytics est désactivé
  # Pourquoi : le mode test de Marvin (admin) ne doit pas fausser les statistiques
  test "umami_enabled? est faux pour un utilisateur admin" do
    # Arrange — User.new suffit : admin? lit juste l'attribut, pas besoin de la base
    ENV["UMAMI_WEBSITE_ID"] = "test-website-id"
    self.current_user = User.new(admin: true)

    # Assert
    assert_not umami_enabled?,
               "L'analytics ne doit pas être actif pour un compte admin"
  end

  # Avec la variable d'env et un utilisateur non-admin connecté, l'analytics est actif
  # Pourquoi : un parent abonné normal doit être tracké comme n'importe quel visiteur
  test "umami_enabled? est vrai pour un utilisateur non-admin connecté" do
    # Arrange
    ENV["UMAMI_WEBSITE_ID"] = "test-website-id"
    self.current_user = User.new(admin: false)

    # Assert
    assert umami_enabled?,
           "L'analytics doit être actif pour un utilisateur non-admin connecté"
  end
end
