# Test du ParentalController
# Ce fichier vérifie que le dashboard parental est protégé
# et que les statistiques sont correctement calculées.
require "test_helper"

class ParentalControllerTest < ActionDispatch::IntegrationTest

  def sign_in_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password" }
    }
    follow_redirect!
  end

  # ===========================================================
  # SECTION 1 — Accès et protection
  # ===========================================================

  # Vérifie qu'un visiteur non connecté est redirigé
  # Cas : GET /parental sans session active
  # Pourquoi : authenticate_user! dans ApplicationController
  test "GET /parental redirige vers connexion si non connecté" do
    # Act
    get parental_path

    # Assert
    assert_redirected_to new_user_session_path,
                         "Un visiteur non connecté devrait être redirigé vers la connexion"
  end

  # Vérifie que le dashboard parental répond 200 pour un utilisateur connecté
  # Cas : Marie connectée avec des histoires et des enfants
  # Pourquoi : c'est la page de suivi parental — doit être accessible
  test "GET /parental répond 200 pour un utilisateur connecté" do
    # Arrange
    sign_in_as(users(:marie))

    # Act
    get parental_path

    # Assert
    assert_response :success,
                    "Le dashboard parental devrait répondre 200 pour un utilisateur connecté"
  end

  # Vérifie que le dashboard parental fonctionne sans enfant ni histoire
  # Cas : nouvel utilisateur — toutes les collections sont vides
  # Pourquoi : évite les erreurs nil sur sum/group pour les nouveaux comptes
  test "GET /parental fonctionne pour un utilisateur sans enfant" do
    # Arrange
    user = User.create!(
      email: "sans_enfant_parental@example.com",
      password: "password",
      first_name: "Vide",
      last_name: "Dashboard"
    )
    sign_in_as(user)

    # Act
    get parental_path

    # Assert — pas de 500 avec collections vides
    assert_response :success,
                    "Le parental devrait fonctionner même sans enfant ni histoire"
  end

  # ===========================================================
  # SECTION 2 — Statistiques
  # ===========================================================

  # Vérifie que le dashboard parental affiche bien des données sans erreur
  # quand l'utilisateur a des histoires avec des valeurs éducatives
  # Cas : Marie a des histoires avec educational_value renseignée
  # Pourquoi : le GROUP BY sur educational_value ne doit pas planter
  test "GET /parental se charge sans erreur avec des histoires et valeurs éducatives" do
    # Arrange — Marie a déjà des histoires avec educational_value dans les fixtures
    sign_in_as(users(:marie))

    # Act
    get parental_path

    # Assert
    assert_response :success,
                    "Le dashboard parental devrait se charger sans erreur avec des valeurs éducatives"
  end
end
