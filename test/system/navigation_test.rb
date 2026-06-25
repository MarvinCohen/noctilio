# ============================================================
# Tests système — Navigation (smoke tests des pages connectées)
# ============================================================
# Vérifie que les pages clés accessibles APRÈS connexion se rendent sans
# erreur (pas d'exception de vue, pas d'écran blanc). Les formulaires enfant /
# histoire étant des assistants complexes (inputs custom + JS), on ne soumet
# pas ici : on s'assure seulement que les pages chargent pour un parent connecté.
# La logique de création est couverte par les tests de controllers.
# Lancement : bin/rails test:system
# ============================================================
require "application_system_test_case"

class NavigationTest < ApplicationSystemTestCase
  setup do
    # On utilise le compte admin : il est premium (premier? renvoie true), donc
    # jamais bloqué par le quota gratuit qui redirigerait /stories/new vers /abonnement.
    @user = users(:admin_user)
    # On lui crée un enfant : sans aucun profil enfant, /stories/new redirige
    # vers /children/new (on ne peut pas créer d'histoire sans héros).
    @user.children.create!(name: "Astro", age: 6, gender: "boy")
    sign_in_as(@user)
  end

  # Le dashboard se rend pour un utilisateur connecté.
  test "le dashboard se charge après connexion" do
    visit dashboard_path
    assert_current_path dashboard_path
  end

  # La page de création d'un profil enfant se rend sans erreur.
  test "la page de création d'un enfant se charge" do
    visit new_child_path
    assert_current_path new_child_path
  end

  # La page de création d'une histoire se rend sans erreur.
  test "la page de création d'une histoire se charge" do
    visit new_story_path
    assert_current_path new_story_path
  end

  private

  # Petit helper de connexion via le vrai formulaire (réutilisé par chaque test).
  def sign_in_as(user)
    visit new_user_session_path
    fill_in "user_email",    with: user.email
    fill_in "user_password", with: "password"
    click_button "Se connecter"
    # On attend d'être bien redirigé sur le dashboard avant de continuer
    assert_current_path dashboard_path
  end
end
