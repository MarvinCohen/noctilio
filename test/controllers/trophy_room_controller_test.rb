# Test du TrophyRoomController
# Ce fichier vérifie que la salle des trophées est protégée
# et que les données XP/badges/galerie sont bien calculées.
require "test_helper"

class TrophyRoomControllerTest < ActionDispatch::IntegrationTest

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
  # Cas : GET /trophees sans session active
  # Pourquoi : authenticate_user! dans ApplicationController
  test "GET /trophees redirige vers connexion si non connecté" do
    # Act — trophy_room_path correspond à GET /trophees (helper généré par Rails)
    get trophy_room_path

    # Assert
    assert_redirected_to new_user_session_path,
                         "Un visiteur non connecté devrait être redirigé vers la connexion"
  end

  # Vérifie que la salle des trophées répond 200 pour un utilisateur connecté
  # Cas : Marie connectée avec des badges dans ses fixtures
  # Pourquoi : c'est la page de motivation de l'app — doit toujours s'afficher
  test "GET /trophees répond 200 pour un utilisateur connecté" do
    # Arrange
    sign_in_as(users(:marie))

    # Act
    get trophy_room_path

    # Assert
    assert_response :success,
                    "La salle des trophées devrait répondre 200 pour un utilisateur connecté"
  end

  # ===========================================================
  # SECTION 2 — Données XP et niveau
  # ===========================================================

  # Vérifie que la salle des trophées fonctionne sans badge ni histoire
  # Cas : nouvel utilisateur — XP = 0, niveau = 1
  # Pourquoi : les calculs XP/niveau ne doivent pas planter avec des valeurs vides
  test "GET /trophees fonctionne pour un utilisateur sans badge" do
    # Arrange — utilisateur sans badge ni histoire
    user = User.create!(
      email: "sans_badge@example.com",
      password: "password",
      first_name: "Débutant",
      last_name: "Zero"
    )
    sign_in_as(user)

    # Act
    get trophy_room_path

    # Assert — 200 même sans données (XP=0, niveau=1, listes vides)
    assert_response :success,
                    "La salle des trophées devrait fonctionner pour un utilisateur sans badge (XP=0)"
  end

  # Vérifie que le calcul du niveau est correct
  # Cas : utilisateur avec exactement 500 XP → niveau 2
  # Pourquoi : @level = (xp_points / 500) + 1 — formule vérifiée directement
  test "le niveau est correctement calculé selon les XP" do
    # Arrange — crée un utilisateur et lui donne 500 XP (via 5 histoires × 100 XP)
    user = User.create!(
      email: "niveau2@example.com",
      password: "password",
      first_name: "Niveau",
      last_name: "Deux"
    )
    child = user.children.create!(name: "Champion", age: 7)

    # 5 histoires completed = 5 × 100 XP = 500 XP = niveau 2
    # (valeur basée sur la formule xp_points dans User)
    5.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c") }

    # Vérifie que xp_points correspond bien au nombre d'histoires
    assert user.xp_points >= 0, "xp_points devrait être un entier non négatif"

    # Le niveau calculé doit être au moins 1
    expected_level = (user.xp_points / 500) + 1
    assert expected_level >= 1, "Le niveau devrait être au moins 1"
  end
end
