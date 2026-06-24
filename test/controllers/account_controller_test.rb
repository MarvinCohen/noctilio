# Test du AccountController
# Ce fichier vérifie l'espace "Mon compte" :
# - La page est protégée par l'authentification Devise
# - Le bouton "mode test" (passage admin) est strictement réservé
#   aux emails de la liste blanche AUTHORIZED_TEST_EMAILS
# C'est une garde de sécurité critique : sans elle, n'importe quel
# utilisateur pourrait se rendre admin et débloquer le premium gratuitement.
require "test_helper"

class AccountControllerTest < ActionDispatch::IntegrationTest
  # ===========================================================
  # HELPER — connexion Devise (même approche que StoriesControllerTest)
  # ===========================================================
  # Poste sur la session Devise puis suit la redirection vers le dashboard
  def sign_in_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password" }
    }
    follow_redirect!
  end

  # ===========================================================
  # SECTION 1 — GET /mon-compte (show)
  # ===========================================================

  # Vérifie que la page redirige vers la connexion si non connecté
  # Cas : visiteur anonyme
  # Pourquoi : authenticate_user! global — les infos du compte sont privées
  test "GET /mon-compte redirige vers connexion si non connecté" do
    # Act
    get account_path

    # Assert
    assert_redirected_to new_user_session_path,
                         "Un visiteur non connecté devrait être redirigé vers la connexion"
  end

  # Vérifie que la page s'affiche pour un utilisateur connecté
  # Cas : Marie connectée consulte son compte
  # Pourquoi : cas nominal — la page doit répondre 200
  test "GET /mon-compte affiche la page pour un utilisateur connecté" do
    # Arrange
    sign_in_as(users(:marie))

    # Act
    get account_path

    # Assert
    assert_response :success,
                    "La page Mon compte devrait répondre 200 pour un utilisateur connecté"
  end

  # ===========================================================
  # SECTION 2 — POST /mon-compte/mode-test (toggle_test_mode)
  # ===========================================================

  # Vérifie qu'un email NON autorisé ne peut pas activer le mode test
  # Cas : Marie (marie@example.com — pas dans la liste blanche) forge le POST
  # Pourquoi : la garde serveur doit bloquer même si le bouton est masqué dans la vue
  test "POST mode-test est refusé pour un email non autorisé" do
    # Arrange
    user = users(:marie)
    sign_in_as(user)
    assert_not user.admin?, "Pré-condition : Marie ne doit pas être admin"

    # Act — requête forgée (le bouton n'est même pas affiché pour Marie)
    post account_toggle_test_mode_path

    # Assert 1 — redirigé avec une alerte (pas de notice de succès)
    assert_redirected_to account_path
    assert_equal "Action non autorisée.", flash[:alert],
                 "Une alerte devrait indiquer le refus"

    # Assert 2 — le statut admin n'a PAS changé en base
    user.reload
    assert_not user.admin?,
               "Marie ne doit pas devenir admin via une requête forgée"
  end

  # Vérifie qu'un email autorisé PEUT activer puis désactiver le mode test
  # Cas : compte avec l'email de la liste blanche (créé à la volée — pas en fixture
  # pour ne pas exposer un compte admin-able dans les données de test partagées)
  # Pourquoi : c'est la fonctionnalité attendue pour les tests manuels de Marvin
  test "POST mode-test bascule le statut admin pour un email autorisé" do
    # Arrange — crée un utilisateur avec l'email autorisé
    user = User.create!(
      email: AccountController::AUTHORIZED_TEST_EMAILS.first,
      password: "password",
      first_name: "Marvin",
      last_name: "Cohen"
    )
    sign_in_as(user)
    assert_not user.admin?, "Pré-condition : le compte démarre non admin"

    # Act 1 — active le mode test
    post account_toggle_test_mode_path

    # Assert 1 — devenu admin (donc premium? = true)
    user.reload
    assert user.admin?, "Le compte autorisé devrait devenir admin (mode test activé)"
    assert_redirected_to account_path

    # Act 2 — désactive le mode test (deuxième bascule)
    post account_toggle_test_mode_path

    # Assert 2 — redevenu non admin
    user.reload
    assert_not user.admin?, "La deuxième bascule devrait désactiver le mode test"
  end

  # ===========================================================
  # SECTION 3 — GET /mon-compte/export (export RGPD)
  # ===========================================================

  # Vérifie que l'export redirige vers la connexion si non connecté
  # Cas : visiteur anonyme
  # Pourquoi : les données personnelles ne doivent être accessibles qu'au propriétaire connecté
  test "GET /mon-compte/export redirige vers connexion si non connecté" do
    # Act
    get account_export_path

    # Assert
    assert_redirected_to new_user_session_path,
                         "L'export doit être protégé par l'authentification"
  end

  # Vérifie que l'export renvoie un téléchargement JSON pour un utilisateur connecté
  # Cas : Marie connectée télécharge ses données
  # Pourquoi : cas nominal — la réponse doit être un fichier JSON en pièce jointe
  test "GET /mon-compte/export renvoie un fichier JSON pour un utilisateur connecté" do
    # Arrange
    sign_in_as(users(:marie))

    # Act
    get account_export_path

    # Assert 1 — réponse 200 + type JSON
    assert_response :success
    assert_equal "application/json", response.media_type,
                 "L'export devrait être servi en application/json"

    # Assert 2 — en-tête de téléchargement (pièce jointe, pas affichage écran)
    assert_match(/attachment/, response.headers["Content-Disposition"].to_s,
                 "L'export devrait être proposé en téléchargement (attachment)")

    # Assert 3 — le JSON contient bien l'email de Marie (données réellement exportées)
    donnees = JSON.parse(response.body)
    assert_equal "marie@example.com", donnees.dig("compte", "email"),
                 "Le JSON exporté devrait contenir l'email de l'utilisateur connecté"
  end
end
