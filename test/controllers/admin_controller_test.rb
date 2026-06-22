# Test de l'AdminController
# Ce fichier vérifie UNIQUEMENT la garde d'accès (require_admin!) : qui peut
# voir les pages d'administration et qui en est exclu. On ne teste pas le contenu
# des pages (waitlist / feedbacks) — seulement la protection, car c'est elle qui
# empêche un utilisateur lambda de consulter les emails et retours des autres.
require "test_helper"

class AdminControllerTest < ActionDispatch::IntegrationTest

  # Connecte un utilisateur via le formulaire Devise (comme un vrai login)
  # Le mot de passe "password" correspond à l'encrypted_password des fixtures.
  def sign_in_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password" }
    }
    follow_redirect!
  end

  # ===========================================================
  # SECTION 1 — Visiteur non connecté
  # ===========================================================

  # Vérifie qu'un visiteur anonyme ne peut pas atteindre /admin/waitlist
  # Cas : aucune session → authenticate_user! (ApplicationController) intercepte
  # Pourquoi : les emails de la liste d'attente ne doivent jamais fuiter
  test "GET /admin/waitlist redirige vers la connexion si non connecté" do
    get admin_waitlist_path

    assert_redirected_to new_user_session_path,
                         "La liste d'attente devrait être inaccessible sans connexion"
  end

  # Vérifie qu'un visiteur anonyme ne peut pas atteindre /admin/feedbacks
  # Cas : aucune session → authenticate_user! intercepte avant require_admin!
  # Pourquoi : les retours utilisateurs sont des données privées
  test "GET /admin/feedbacks redirige vers la connexion si non connecté" do
    get admin_feedbacks_path

    assert_redirected_to new_user_session_path,
                         "Les retours devraient être inaccessibles sans connexion"
  end

  # ===========================================================
  # SECTION 2 — Utilisateur connecté mais NON admin
  # ===========================================================

  # Vérifie qu'un compte standard (Marie) est refusé sur /admin/waitlist
  # Cas : connecté mais admin? == false → require_admin! redirige vers le dashboard
  # Pourquoi : c'est le cœur de la garde — un utilisateur lambda ne doit rien voir
  test "GET /admin/waitlist redirige un non-admin vers le dashboard" do
    sign_in_as(users(:marie))

    get admin_waitlist_path

    assert_redirected_to dashboard_path,
                         "Un non-admin devrait être renvoyé vers son dashboard"
    assert_equal "Accès non autorisé.", flash[:alert]
  end

  # Vérifie qu'un compte standard (Marie) est refusé sur /admin/feedbacks
  # Cas : connecté mais admin? == false → require_admin! redirige vers le dashboard
  # Pourquoi : même garde que waitlist, on s'assure qu'elle couvre les deux actions
  test "GET /admin/feedbacks redirige un non-admin vers le dashboard" do
    sign_in_as(users(:marie))

    get admin_feedbacks_path

    assert_redirected_to dashboard_path,
                         "Un non-admin devrait être renvoyé vers son dashboard"
    assert_equal "Accès non autorisé.", flash[:alert]
  end

  # ===========================================================
  # SECTION 3 — Utilisateur admin (accès autorisé)
  # ===========================================================

  # Vérifie que l'admin accède bien à la liste d'attente
  # Cas : admin? == true → require_admin! laisse passer → la page se charge
  # Pourquoi : la garde ne doit pas bloquer les ayants droit
  test "GET /admin/waitlist s'affiche pour un admin" do
    sign_in_as(users(:admin_user))

    get admin_waitlist_path

    assert_response :success,
                    "Un admin devrait pouvoir consulter la liste d'attente"
  end

  # Vérifie que l'admin accède bien aux retours
  # Cas : admin? == true → require_admin! laisse passer → la page se charge
  # Pourquoi : la garde ne doit pas bloquer les ayants droit
  test "GET /admin/feedbacks s'affiche pour un admin" do
    sign_in_as(users(:admin_user))

    get admin_feedbacks_path

    assert_response :success,
                    "Un admin devrait pouvoir consulter les retours"
  end
end
