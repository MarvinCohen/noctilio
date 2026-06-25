# ============================================================
# Tests système — Authentification (connexion / garde d'accès)
# ============================================================
# Ces tests pilotent un vrai navigateur (Chrome headless via Selenium)
# pour vérifier les parcours critiques de connexion de bout en bout.
# Lancement : bin/rails test:system
# ============================================================
require "application_system_test_case"

class AuthenticationTest < ApplicationSystemTestCase
  # On réutilise la fixture "marie" (mot de passe "password", voir users.yml)
  setup do
    @marie = users(:marie)
  end

  # Un utilisateur existant se connecte avec les bons identifiants
  # et arrive bien sur le dashboard (/home).
  test "connexion réussie redirige vers le dashboard" do
    visit new_user_session_path

    # On remplit le formulaire par l'id généré par Simple Form (user_email / user_password)
    fill_in "user_email",    with: @marie.email
    fill_in "user_password", with: "password"
    click_button "Se connecter"

    # after_sign_in_path_for renvoie vers dashboard_path (= /home)
    assert_current_path dashboard_path
  end

  # Un mauvais mot de passe ne connecte pas : on reste sur la page de connexion.
  test "connexion échouée reste sur la page de connexion" do
    visit new_user_session_path

    fill_in "user_email",    with: @marie.email
    fill_in "user_password", with: "mauvais_mot_de_passe"
    click_button "Se connecter"

    # Devise renvoie vers le formulaire de connexion (création de session échouée)
    assert_current_path new_user_session_path
  end

  # Garde d'authentification : une page privée (dashboard) n'est pas accessible
  # sans connexion → Devise redirige vers le formulaire de connexion.
  test "page privée inaccessible sans connexion redirige vers la connexion" do
    visit dashboard_path

    assert_current_path new_user_session_path
  end
end
