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

  # content_security_policy_nonce : fourni par Rails dans un vrai rendu de vue,
  # mais absent du contexte isolé d'un test de helper. On le stub avec une valeur
  # factice pour que umami_event_tag puisse construire son <script nonce="...">.
  def content_security_policy_nonce
    "test-nonce"
  end

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

  # ============================================================
  # umami_event_tag — émission d'événements de funnel
  # ============================================================

  # Sans la variable d'env (cas dev/test), aucun script d'événement ne doit
  # être rendu — c'est la preuve que le tracking est bien coupé en local/CI.
  test "umami_event_tag ne rend rien quand l'analytics est désactivé" do
    # Arrange — pas d'UMAMI_WEBSITE_ID → umami_enabled? est false
    ENV.delete("UMAMI_WEBSITE_ID")
    self.current_user = nil

    # Assert — même avec un événement valide, la sortie est vide
    assert_nil umami_event_tag("signup"),
               "Aucun script ne doit être rendu quand l'analytics est coupé"
  end

  # Analytics actif + événement en liste blanche → un <script> appelant
  # umami.track avec le bon nom d'événement est rendu.
  test "umami_event_tag rend le script pour un événement connu" do
    # Arrange
    ENV["UMAMI_WEBSITE_ID"] = "test-website-id"
    self.current_user = nil

    # Act
    tag = umami_event_tag("signup")

    # Assert — le nom de l'événement est bien injecté dans l'appel umami.track
    assert_includes tag, "umami.track(\"signup\")",
                    "Le script doit tracker l'événement demandé"
  end

  # Analytics actif MAIS événement hors liste blanche → rien (anti-injection).
  # C'est la garde de sécurité : un nom arbitraire ne finit jamais dans le HTML.
  test "umami_event_tag ne rend rien pour un événement inconnu" do
    # Arrange
    ENV["UMAMI_WEBSITE_ID"] = "test-website-id"
    self.current_user = nil

    # Assert — un nom non listé est refusé silencieusement
    assert_nil umami_event_tag("evenement_pirate"),
               "Un événement hors liste blanche ne doit jamais être rendu"
  end

  # Analytics actif mais aucun événement fourni (nil) → rien à émettre.
  # Cas nominal d'une page sans flash[:umami_event].
  test "umami_event_tag ne rend rien quand le nom est nil" do
    # Arrange
    ENV["UMAMI_WEBSITE_ID"] = "test-website-id"
    self.current_user = nil

    # Assert
    assert_nil umami_event_tag(nil),
               "Sans nom d'événement, aucun script ne doit être rendu"
  end
end
