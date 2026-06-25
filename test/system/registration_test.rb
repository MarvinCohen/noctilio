# ============================================================
# Tests système — Inscription (création de compte)
# ============================================================
# Vérifie qu'un nouveau parent peut créer un compte de bout en bout
# via le vrai formulaire d'inscription, et qu'il atterrit connecté.
# Lancement : bin/rails test:system
# ============================================================
require "application_system_test_case"

class RegistrationTest < ApplicationSystemTestCase
  # Un nouvel utilisateur remplit le formulaire d'inscription et se retrouve
  # connecté sur le dashboard. (Avec :confirmable + période de grâce de 7 jours,
  # l'accès reste ouvert immédiatement après l'inscription.)
  test "inscription d'un nouveau compte redirige vers le dashboard" do
    visit new_user_registration_path

    # Champs Simple Form du RegistrationsController personnalisé (first_name/last_name autorisés)
    fill_in "user_first_name",            with: "Nouveau"
    fill_in "user_last_name",             with: "Parent"
    fill_in "user_email",                 with: "nouveau.parent@example.com"
    fill_in "user_password",              with: "motdepasse123"
    fill_in "user_password_confirmation", with: "motdepasse123"

    # Le bouton porte le libellé exact défini dans la vue d'inscription
    click_button "Créer mon compte ✨"

    # Après inscription, Devise connecte le compte et after_sign_up redirige vers /home
    assert_current_path dashboard_path

    # Le compte a bien été persisté en base
    assert User.exists?(email: "nouveau.parent@example.com")
  end

  # Deux mots de passe différents → le compte n'est pas créé, on reste sur le formulaire.
  test "inscription échoue si les mots de passe ne correspondent pas" do
    visit new_user_registration_path

    fill_in "user_first_name",            with: "Erreur"
    fill_in "user_last_name",             with: "Test"
    fill_in "user_email",                 with: "erreur.test@example.com"
    fill_in "user_password",              with: "motdepasse123"
    fill_in "user_password_confirmation", with: "autremotdepasse"
    click_button "Créer mon compte ✨"

    # Aucun compte créé avec cet email
    assert_not User.exists?(email: "erreur.test@example.com")
  end
end
