# Test du BadgesController
# Vérifie l'accusé de notification des badges (POST /badges/vus) :
# protection par authentification + bascule des badges en notified: true.
require "test_helper"

class BadgesControllerTest < ActionDispatch::IntegrationTest

  def sign_in_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password" }
    }
    follow_redirect!
  end

  # ===========================================================
  # SECTION 1 — Accès et protection
  # ===========================================================

  # Vérifie qu'un visiteur non connecté ne peut pas appeler l'endpoint
  # Pourquoi : authenticate_user! dans ApplicationController
  test "POST /badges/vus redirige vers connexion si non connecté" do
    post mark_badges_seen_path

    assert_redirected_to new_user_session_path,
                         "Un visiteur non connecté devrait être redirigé vers la connexion"
  end

  # ===========================================================
  # SECTION 2 — Bascule notified
  # ===========================================================

  # Vérifie que l'endpoint marque les badges en attente comme notifiés
  # Cas : Marie a un badge non notifié (fixture) → après l'appel, il est notifié
  # Pourquoi : c'est ce qui empêche de re-fêter un badge à chaque chargement
  test "POST /badges/vus marque les badges en attente comme notifiés" do
    # Arrange — on s'assure que Marie a au moins un badge non notifié
    marie = users(:marie)
    marie.user_badges.update_all(notified: false)
    assert marie.user_badges.unnotified.exists?,
           "Marie devrait avoir au moins un badge non notifié avant l'appel"

    sign_in_as(marie)

    # Act
    post mark_badges_seen_path

    # Assert — plus aucun badge non notifié, réponse 200
    assert_response :success
    assert_not marie.reload.user_badges.unnotified.exists?,
               "Tous les badges de Marie devraient être notifiés après l'appel"
  end
end
