# Test du ChildrenController
# Ce fichier vérifie les actions CRUD sur les profils enfants :
# - Les utilisateurs non connectés sont redirigés
# - Un utilisateur ne peut pas accéder aux enfants d'un autre utilisateur
# - Les créations et suppressions fonctionnent correctement
require "test_helper"

class ChildrenControllerTest < ActionDispatch::IntegrationTest

  # ===========================================================
  # HELPER — connexion Devise
  # ===========================================================

  # Connecte un utilisateur via POST sur la session Devise
  # Même helper que dans StoriesControllerTest — patron standard de l'app
  def sign_in_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password" }
    }
    follow_redirect!
  end

  # ===========================================================
  # SECTION 1 — GET /children (index)
  # ===========================================================

  # Vérifie qu'un visiteur non connecté est redirigé vers la connexion
  # Cas : requête GET sans session active
  # Pourquoi : authenticate_user! protège toutes les pages de l'app
  test "GET /children redirige vers connexion si non connecté" do
    # Act
    get children_path

    # Assert
    assert_redirected_to new_user_session_path,
                         "Un visiteur non connecté devrait être redirigé vers la connexion"
  end

  # Vérifie que l'index affiche les enfants de l'utilisateur connecté
  # Cas : Marie connectée, elle a Léo et Emma comme enfants
  # Pourquoi : la liste des profils est la page de gestion principale des familles
  test "GET /children affiche la liste des enfants pour un utilisateur connecté" do
    # Arrange
    sign_in_as(users(:marie))

    # Act
    get children_path

    # Assert
    assert_response :success,
                    "L'index devrait répondre 200 pour un utilisateur connecté"
  end

  # ===========================================================
  # SECTION 2 — GET /children/new (formulaire de création)
  # ===========================================================

  # Vérifie que le formulaire de création est accessible
  # Cas : Marie connectée, veut créer un nouveau profil enfant
  # Pourquoi : les utilisateurs créent des profils avant de générer des histoires
  test "GET /children/new affiche le formulaire de création" do
    # Arrange
    sign_in_as(users(:marie))

    # Act
    get new_child_path

    # Assert
    assert_response :success,
                    "Le formulaire de création devrait être accessible à un utilisateur connecté"
  end

  # ===========================================================
  # SECTION 3 — POST /children (create)
  # ===========================================================

  # Vérifie qu'un enfant valide est créé et redirige vers la liste
  # Cas : données valides soumises via le formulaire
  # Pourquoi : le flux principal — l'utilisateur crée un profil pour son enfant
  test "POST /children crée un enfant valide et redirige" do
    # Arrange
    sign_in_as(users(:marie))

    # Compte avant création pour vérifier qu'un seul enfant est ajouté
    count_before = users(:marie).children.count

    # Act — soumet des données valides pour un nouvel enfant
    post children_path, params: {
      child: {
        name: "Zoé",
        age: 5,
        gender: "girl"
      }
    }

    # Assert 1 — redirection vers la liste des enfants après succès
    assert_redirected_to children_path,
                          "Après création réussie, on devrait être redirigé vers /children"

    # Assert 2 — un enfant supplémentaire a bien été créé
    assert_equal count_before + 1, users(:marie).reload.children.count,
                 "Un nouvel enfant devrait avoir été créé en base"
  end

  # Vérifie qu'un enfant invalide (sans nom) réaffiche le formulaire
  # Cas : nom manquant dans les paramètres
  # Pourquoi : la validation name: presence true doit bloquer la sauvegarde
  test "POST /children avec données invalides réaffiche le formulaire" do
    # Arrange
    sign_in_as(users(:marie))
    count_before = users(:marie).children.count

    # Act — soumet un enfant sans nom (invalide)
    post children_path, params: {
      child: { name: "", age: 5, gender: "girl" }
    }

    # Assert 1 — on reste sur le formulaire (422 Unprocessable Entity)
    assert_response :unprocessable_entity,
                    "Des données invalides devraient réafficher le formulaire avec une erreur"

    # Assert 2 — aucun enfant créé
    assert_equal count_before, users(:marie).reload.children.count,
                 "Aucun enfant ne devrait être créé avec des données invalides"
  end

  # ===========================================================
  # SECTION 4 — GET /children/:id (show)
  # ===========================================================

  # Vérifie que Marie peut voir le profil de Léo (son enfant)
  # Cas : l'enfant appartient bien à l'utilisateur connecté
  # Pourquoi : set_child cherche dans current_user.children — autorisation implicite
  test "GET /children/:id affiche le profil de son propre enfant" do
    # Arrange
    sign_in_as(users(:marie))

    # Act
    get child_path(children(:leo))

    # Assert
    assert_response :success,
                    "Marie devrait pouvoir voir le profil de Léo (son enfant)"
  end

  # Vérifie que Marie NE PEUT PAS voir le profil de Théo (enfant de Paul)
  # Cas : l'enfant appartient à un autre utilisateur
  # Pourquoi : set_child fait un find dans current_user.children — si l'ID n'est pas là → 404 géré
  test "GET /children/:id redirige si l'enfant appartient à un autre utilisateur" do
    # Arrange — Marie essaie de voir le profil de Théo (appartient à Paul)
    sign_in_as(users(:marie))

    # Act
    get child_path(children(:theo))

    # Assert — le controller redirige avec une alerte
    assert_redirected_to children_path,
                          "Marie ne devrait pas pouvoir voir le profil de Théo (appartient à Paul)"
  end

  # ===========================================================
  # SECTION 5 — DELETE /children/:id (destroy)
  # ===========================================================

  # Vérifie que Marie peut supprimer son propre enfant
  # Cas : suppression d'un enfant qui appartient bien à l'utilisateur
  # Pourquoi : le parent doit pouvoir gérer ses propres profils
  test "DELETE /children/:id supprime son propre enfant et redirige" do
    # Arrange
    sign_in_as(users(:marie))

    # Crée un enfant spécifique pour ce test — on ne veut pas supprimer leo ou emma
    # qui sont utilisés dans d'autres tests
    child_to_delete = users(:marie).children.create!(name: "À supprimer", age: 4)

    count_before = users(:marie).children.count

    # Act
    delete child_path(child_to_delete)

    # Assert 1 — redirection vers la liste
    assert_redirected_to children_path,
                          "Après suppression, on devrait être redirigé vers /children"

    # Assert 2 — l'enfant n'existe plus en base
    assert_equal count_before - 1, users(:marie).reload.children.count,
                 "L'enfant devrait avoir été supprimé de la base"
  end

  # Vérifie que Marie NE PEUT PAS supprimer l'enfant de Paul
  # Cas : tentative de suppression cross-user
  # Pourquoi : set_child protège via current_user.children.find — bloque l'accès
  test "DELETE /children/:id ne supprime pas l'enfant d'un autre utilisateur" do
    # Arrange
    sign_in_as(users(:marie))
    count_before = users(:paul).children.count

    # Act — Marie essaie de supprimer Théo (appartient à Paul)
    delete child_path(children(:theo))

    # Assert — Théo existe toujours
    assert_equal count_before, users(:paul).reload.children.count,
                 "Marie ne devrait pas pouvoir supprimer l'enfant de Paul"
  end

  # ===========================================================
  # SECTION 6 — PATCH /children/:id (update)
  # ===========================================================

  # Vérifie que Marie peut modifier le profil de Léo
  # Cas : mise à jour avec des données valides
  # Pourquoi : les parents doivent pouvoir corriger les informations du profil
  test "PATCH /children/:id met à jour son propre enfant" do
    # Arrange
    sign_in_as(users(:marie))

    # Act — change l'âge de Léo de 6 à 7
    patch child_path(children(:leo)), params: {
      child: { name: "Léo", age: 7, gender: "boy" }
    }

    # Assert 1 — redirection vers le profil mis à jour
    assert_redirected_to child_path(children(:leo)),
                          "Après mise à jour, on devrait être redirigé vers le profil"

    # Assert 2 — l'âge a bien changé en base
    assert_equal 7, children(:leo).reload.age,
                 "L'âge de Léo devrait avoir été mis à jour à 7"
  end
end
