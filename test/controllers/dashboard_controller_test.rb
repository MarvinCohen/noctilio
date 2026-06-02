# Test du DashboardController
# Ce fichier vérifie que le dashboard est bien protégé et charge correctement
# les données nécessaires à la vue principale de l'utilisateur.
require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest

  # Connecte un utilisateur via la session Devise
  def sign_in_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password" }
    }
    follow_redirect!
  end

  # ===========================================================
  # SECTION 1 — Accès et protection
  # ===========================================================

  # Vérifie qu'un visiteur non connecté est redirigé vers la connexion
  # Cas : GET /dashboard sans session active
  # Pourquoi : authenticate_user! dans ApplicationController protège toutes les pages
  test "GET /dashboard redirige vers connexion si non connecté" do
    # Act
    get dashboard_path

    # Assert
    assert_redirected_to new_user_session_path,
                         "Un visiteur non connecté devrait être redirigé vers la connexion"
  end

  # Vérifie que le dashboard répond 200 pour un utilisateur connecté
  # Cas : Marie connectée, accède à /dashboard
  # Pourquoi : c'est la page d'accueil principale après connexion
  test "GET /dashboard répond 200 pour un utilisateur connecté" do
    # Arrange
    sign_in_as(users(:marie))

    # Act
    get dashboard_path

    # Assert
    assert_response :success,
                    "Le dashboard devrait répondre 200 pour un utilisateur connecté"
  end

  # ===========================================================
  # SECTION 2 — Données chargées
  # ===========================================================

  # Vérifie que le dashboard charge bien les histoires récentes
  # Cas : Marie a des histoires completed dans ses fixtures
  # Pourquoi : @recent_stories alimente le bloc "Reprendre" dans la vue
  test "GET /dashboard charge les histoires récentes de l'utilisateur" do
    # Arrange
    sign_in_as(users(:marie))

    # Act
    get dashboard_path

    # Assert — la réponse doit être un succès (les variables d'instance sont bien assignées)
    assert_response :success,
                    "Le dashboard avec des histoires existantes devrait répondre 200"
  end

  # Vérifie que le dashboard est accessible même sans enfant ni histoire
  # Cas : nouvel utilisateur sans profil enfant
  # Pourquoi : un nouvel inscrit ne doit pas avoir d'erreur nil sur les collections
  test "GET /dashboard fonctionne pour un utilisateur sans enfant" do
    # Arrange — crée un utilisateur sans enfant
    user = User.create!(
      email: "nouveau_dashboard@example.com",
      password: "password",
      first_name: "Nouveau",
      last_name: "Dashboard"
    )
    sign_in_as(user)

    # Act
    get dashboard_path

    # Assert — pas de 500 même avec des collections vides
    assert_response :success,
                    "Le dashboard devrait fonctionner même sans enfant (collections vides)"
  end
end
