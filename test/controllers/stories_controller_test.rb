# Test du StoriesController
# Ce fichier vérifie que chaque action du controller répond correctement :
# - Les utilisateurs non connectés sont redirigés vers la connexion
# - Les utilisateurs connectés accèdent à leurs propres ressources
# - Les autorisations croisées sont bien bloquées (Marie ne voit pas les histoires de Paul)
# - Le job de génération est bien lancé à la création
require "test_helper"

class StoriesControllerTest < ActionDispatch::IntegrationTest
  # ActiveJob::TestHelper fournit assert_enqueued_with, assert_no_enqueued_jobs, etc.
  # Sans ce module, les jobs ne sont pas capturés et assert_enqueued_with échoue.
  include ActiveJob::TestHelper

  # ===========================================================
  # HELPER — connexion Devise dans les tests d'intégration
  # ===========================================================
  # Rails + Devise ne fournit pas sign_in directement dans les tests d'intégration.
  # On utilise la méthode helper incluse via devise :database_authenticatable
  # La façon la plus simple en integration test : poster sur la session Devise.
  #
  # Méthode utilitaire privée pour se connecter en tant qu'utilisateur donné.
  # Appelée dans chaque test qui nécessite une session active.
  def sign_in_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password" }
    }
    # Vérifie que la connexion a bien fonctionné (redirection vers dashboard)
    # Si ce n'est pas le cas, le test plantera sur la prochaine assertion
    follow_redirect!
  end

  # ===========================================================
  # SECTION 1 — GET /stories (index)
  # ===========================================================

  # Vérifie que l'index redirige vers la connexion si l'utilisateur n'est pas connecté
  # Cas : visiteur anonyme
  # Pourquoi : authenticate_user! est dans ApplicationController — toutes les pages sont protégées
  test "GET /stories redirige vers connexion si non connecté" do
    # Act — accède à l'index sans être connecté
    get stories_path

    # Assert — Devise doit rediriger vers la page de connexion
    assert_redirected_to new_user_session_path,
                         "Un visiteur non connecté devrait être redirigé vers la connexion"
  end

  # Vérifie que l'index affiche les histoires de l'utilisateur connecté
  # Cas : utilisateur connecté avec des histoires sauvegardées
  # Pourquoi : la bibliothèque personnelle doit être accessible à l'utilisateur connecté
  test "GET /stories affiche la bibliothèque pour un utilisateur connecté" do
    # Arrange — on se connecte en tant que Marie
    sign_in_as(users(:marie))

    # Act — accède à la liste des histoires
    get stories_path

    # Assert — la réponse doit être 200 OK
    assert_response :success,
                    "L'index devrait répondre 200 pour un utilisateur connecté"
  end

  # Vérifie que l'index ne retourne que les histoires sauvegardées et completed de l'utilisateur
  # Cas : Marie a des histoires saved et non-saved
  # Pourquoi : le controller filtre avec .completed_recent.saved_stories — les autres n'apparaissent pas
  test "GET /stories ne montre que les histoires saved et completed" do
    # Arrange
    sign_in_as(users(:marie))

    # Act
    get stories_path

    # Assert — la réponse doit être un succès
    assert_response :success

    # On vérifie que @stories dans l'instance du controller contient bien des histoires sauvegardées
    # assigns(:stories) donne accès aux variables d'instance du controller
    assigned_stories = controller.instance_variable_get(:@stories)
    assigned_stories.each do |story|
      assert story.saved?,     "Toutes les histoires de l'index doivent être saved"
      assert story.completed?, "Toutes les histoires de l'index doivent être completed"
    end
  end

  # ===========================================================
  # SECTION 2 — GET /stories/new
  # ===========================================================

  # Vérifie que le formulaire de création est inaccessible sans connexion
  # Cas : visiteur anonyme tente d'accéder à /stories/new
  # Pourquoi : authenticate_user! protège toute l'application
  test "GET /stories/new redirige si non connecté" do
    # Act
    get new_story_path

    # Assert
    assert_redirected_to new_user_session_path,
                         "/stories/new devrait rediriger un visiteur non connecté"
  end

  # Vérifie que le formulaire de création est accessible pour un utilisateur connecté avec un enfant
  # Cas : Paul est connecté, a un enfant (Théo), et moins de 3 histoires ce mois
  # Pourquoi : c'est la page principale de l'application pour les utilisateurs actifs
  # Note : on utilise Paul et non Marie car Marie a déjà 5 histoires ce mois (limite = 3)
  # check_story_limit! bloquerait Marie avant même d'afficher le formulaire
  test "GET /stories/new affiche le formulaire pour un utilisateur connecté avec enfant" do
    # Arrange — Paul a 1 histoire ce mois (< 3) et a l'enfant Théo
    sign_in_as(users(:paul))

    # Act
    get new_story_path

    # Assert — doit répondre 200
    assert_response :success,
                    "Le formulaire de création devrait être accessible"
  end

  # Vérifie que /stories/new redirige vers la création d'enfant si l'utilisateur n'en a pas
  # Cas : utilisateur sans enfant — admin_user dans les fixtures
  # Pourquoi : sans enfant, on ne peut pas créer d'histoire — le controller le vérifie
  test "GET /stories/new redirige vers new_child_path si aucun enfant" do
    # Arrange — admin_user n'a pas d'enfant dans les fixtures
    sign_in_as(users(:admin_user))

    # Act
    get new_story_path

    # Assert — doit rediriger vers la création d'un profil enfant
    assert_redirected_to new_child_path,
                         "Sans enfant, /stories/new devrait rediriger vers new_child_path"
  end

  # Vérifie que /stories/new redirige si l'utilisateur a atteint sa limite mensuelle
  # Cas : Paul a 3 histoires ce mois (limit atteinte)
  # Pourquoi : check_story_limit! bloque l'accès avant l'action new
  test "GET /stories/new redirige si limite mensuelle atteinte" do
    # Arrange — on crée 2 histoires supplémentaires pour Paul (il en a déjà 1 via theo)
    user = users(:paul)
    child = children(:theo)
    2.times { child.stories.create!(status: :pending) }

    assert_equal 3, user.stories_this_month,
                 "Pré-condition : Paul doit avoir 3 histoires ce mois"

    sign_in_as(user)

    # Act
    get new_story_path

    # Assert — doit rediriger vers la bibliothèque avec un message d'alerte
    assert_redirected_to stories_path,
                         "Quand la limite est atteinte, /stories/new devrait rediriger"
  end

  # ===========================================================
  # SECTION 3 — POST /stories (create)
  # ===========================================================

  # Vérifie que POST /stories crée une histoire et lance le job de génération
  # Cas : données valides, Paul connecté avec son enfant Théo, moins de 3 histoires ce mois
  # Pourquoi : c'est l'action centrale de l'application — elle doit créer en base et lancer l'IA
  # Note : on utilise Paul (1 histoire ce mois) et non Marie (5 histoires, limite dépassée)
  test "POST /stories crée une histoire et lance GenerateStoryJob" do
    # Arrange
    sign_in_as(users(:paul))

    # On vérifie que le job est bien mis en file d'attente sans l'exécuter réellement
    # (on ne veut PAS appeler l'API OpenAI dans les tests)
    # ActiveJob::TestHelper#assert_enqueued_with capture les jobs en mémoire
    assert_enqueued_with(job: GenerateStoryJob) do
      # Act — envoie une requête POST avec les paramètres du formulaire
      post stories_path, params: {
        story: {
          child_ids: [children(:theo).id],
          world_theme: "space",
          educational_value: "courage",
          duration_minutes: 5,
          interactive: false
        }
      }
    end

    # Assert 1 — l'histoire a bien été créée en base pour l'enfant Théo
    assert Story.where(child: children(:theo)).where("created_at > ?", 10.seconds.ago).exists?,
           "Une histoire devrait avoir été créée en base de données pour Théo"

    # Assert 2 — redirige vers la page de l'histoire (pour afficher le spinner)
    assert_response :redirect
    follow_redirect!
    assert_response :success
  end

  # Vérifie que POST /stories échoue si aucun enfant n'est sélectionné
  # Cas : child_ids vide dans le formulaire
  # Pourquoi : le controller gère ce cas explicitement et re-rend le formulaire
  # Note : on utilise Paul (1 histoire ce mois) pour ne pas être bloqué par check_story_limit!
  test "POST /stories échoue si aucun enfant sélectionné" do
    # Arrange
    sign_in_as(users(:paul))

    # Compte les histoires avant pour vérifier qu'aucune n'est créée
    count_before = Story.count

    # Act — envoie sans child_ids
    post stories_path, params: {
      story: {
        child_ids: [],
        world_theme: "space",
        educational_value: "courage"
      }
    }

    # Assert 1 — aucune histoire créée
    assert_equal count_before, Story.count,
                 "Aucune histoire ne devrait être créée si child_ids est vide"

    # Assert 2 — re-rendu du formulaire avec erreur (statut 422)
    assert_response :unprocessable_entity,
                    "Le formulaire devrait être re-rendu avec une erreur"
  end

  # Vérifie que POST /stories redirige si non connecté
  # Cas : visiteur anonyme tente de poster
  # Pourquoi : authenticate_user! doit bloquer avant même d'atteindre l'action create
  test "POST /stories redirige vers connexion si non connecté" do
    # Act
    post stories_path, params: {
      story: { child_ids: [children(:leo).id], world_theme: "space" }
    }

    # Assert
    assert_redirected_to new_user_session_path
  end

  # ===========================================================
  # SECTION 4 — GET /stories/:id (show)
  # ===========================================================

  # Vérifie qu'un utilisateur peut accéder à sa propre histoire
  # Cas : Marie accède à l'histoire de son enfant Léo
  # Pourquoi : cas nominal de lecture — doit fonctionner pour le propriétaire
  test "GET /stories/:id est accessible par le propriétaire de l'histoire" do
    # Arrange
    sign_in_as(users(:marie))
    story = stories(:completed_saved)

    # Act
    get story_path(story)

    # Assert — doit répondre 200
    assert_response :success,
                    "Le propriétaire doit pouvoir accéder à son histoire"
  end

  # Vérifie qu'un utilisateur ne peut PAS accéder à l'histoire d'un autre utilisateur
  # Cas : Marie tente d'accéder à l'histoire de Paul
  # Pourquoi : set_story filtre par current_user.stories — protection essentielle de la vie privée
  test "GET /stories/:id est refusé pour un autre utilisateur" do
    # Arrange — Marie se connecte, mais tente d'accéder à l'histoire de Paul
    sign_in_as(users(:marie))
    paul_story = stories(:paul_story)  # Cette histoire appartient à Théo (enfant de Paul)

    # Act — Marie tente d'accéder à l'histoire de Paul
    get story_path(paul_story)

    # Assert — doit rediriger (le set_story rescue renvoie vers stories_path)
    assert_redirected_to stories_path,
                         "Marie ne devrait pas pouvoir accéder à l'histoire de Paul"
  end

  # Vérifie que show est inaccessible sans connexion
  # Cas : visiteur anonyme
  # Pourquoi : authenticate_user! doit bloquer avant d'aller plus loin
  test "GET /stories/:id redirige si non connecté" do
    # Arrange
    story = stories(:completed_saved)

    # Act
    get story_path(story)

    # Assert
    assert_redirected_to new_user_session_path
  end

  # ===========================================================
  # SECTION 5 — POST /stories/:id/choose
  # ===========================================================

  # Vérifie que choose enregistre le choix interactif et lance le job de continuation
  # Cas : histoire interactive avec un choix en attente, choix valide ("a" ou "b")
  # Pourquoi : c'est le coeur du mode interactif — le choix doit être persisté et déclencher l'IA
  test "POST /stories/:id/choose enregistre le choix et lance GenerateStoryContinuationJob" do
    # Arrange
    sign_in_as(users(:marie))
    story  = stories(:interactive_story)
    choice = story_choices(:pending_choice)

    # Vérifie la pré-condition
    assert_nil choice.chosen_option,
               "Pré-condition : le choix ne doit pas encore avoir été effectué"

    # On mock GenerateStoryContinuationJob pour éviter d'appeler OpenAI
    assert_enqueued_with(job: GenerateStoryContinuationJob) do
      # Act — envoie le choix "a"
      post choose_story_path(story), params: { chosen_option: "a" }
    end

    # Assert 1 — le choix a bien été persisté en base
    choice.reload  # Recharge depuis la base pour avoir les données fraîches
    assert_equal "a", choice.chosen_option,
                 "Le choix 'a' devrait être sauvegardé en base"

    # Assert 2 — l'histoire repasse en status "generating"
    story.reload
    assert story.generating?,
           "L'histoire devrait repasser en status generating après un choix"
  end

  # Vérifie que choose rejette un choix invalide (pas "a" ni "b")
  # Cas : choix "c" envoyé (manipulation de requête)
  # Pourquoi : le controller valide explicitement que le choix est bien "a" ou "b"
  test "POST /stories/:id/choose rejette un choix invalide" do
    # Arrange
    sign_in_as(users(:marie))
    story = stories(:interactive_story)
    choice = story_choices(:pending_choice)

    # Act — envoie un choix invalide
    post choose_story_path(story), params: { chosen_option: "c" }

    # Assert 1 — redirige avec une alerte
    assert_redirected_to story_path(story),
                         "Un choix invalide devrait rediriger vers l'histoire"

    # Assert 2 — le choix n'a pas été persisté
    choice.reload
    assert_nil choice.chosen_option,
               "chosen_option ne devrait pas être modifié pour un choix invalide"
  end

  # Vérifie que choose est inaccessible pour un utilisateur non connecté
  # Cas : visiteur anonyme poste sur l'endpoint choose
  # Pourquoi : toutes les actions sont protégées par authenticate_user!
  test "POST /stories/:id/choose redirige si non connecté" do
    # Arrange
    story = stories(:interactive_story)

    # Act
    post choose_story_path(story), params: { chosen_option: "a" }

    # Assert
    assert_redirected_to new_user_session_path,
                         "choose devrait rediriger un visiteur non connecté"
  end

  # Vérifie que choose est refusé si l'histoire n'est pas interactive
  # Cas : tentative de choix sur une histoire standard (interactive: false)
  # Pourquoi : le controller vérifie que l'histoire est bien interactive avant d'accepter le choix
  test "POST /stories/:id/choose est refusé pour une histoire non interactive" do
    # Arrange — completed_saved est non interactive
    sign_in_as(users(:marie))
    story = stories(:completed_saved)
    assert_not story.interactive?, "Pré-condition : l'histoire ne doit pas être interactive"

    # Act
    post choose_story_path(story), params: { chosen_option: "a" }

    # Assert — redirige avec un message d'erreur
    assert_redirected_to story_path(story),
                         "choose devrait rediriger si l'histoire n'est pas interactive"
  end

  # ===========================================================
  # SECTION 6 — DELETE /stories/:id (destroy)
  # ===========================================================

  # Vérifie qu'un utilisateur peut supprimer sa propre histoire
  # Cas : Marie supprime une de ses histoires
  # Pourquoi : l'utilisateur doit pouvoir gérer sa bibliothèque
  test "DELETE /stories/:id supprime l'histoire du propriétaire" do
    # Arrange
    sign_in_as(users(:marie))
    story = stories(:completed_saved)
    story_id = story.id

    # Act
    delete story_path(story)

    # Assert 1 — redirige vers la bibliothèque
    assert_redirected_to stories_path,
                         "La suppression devrait rediriger vers /stories"

    # Assert 2 — l'histoire n'existe plus en base
    assert_nil Story.find_by(id: story_id),
               "L'histoire devrait être supprimée de la base de données"
  end

  # Vérifie qu'un utilisateur ne peut pas supprimer l'histoire d'un autre
  # Cas : Marie tente de supprimer l'histoire de Paul
  # Pourquoi : set_story filtre par current_user.stories — Marie ne trouve pas l'histoire de Paul
  test "DELETE /stories/:id ne peut pas supprimer l'histoire d'un autre utilisateur" do
    # Arrange
    sign_in_as(users(:marie))
    paul_story = stories(:paul_story)
    paul_story_id = paul_story.id

    # Act — Marie tente de supprimer l'histoire de Paul
    delete story_path(paul_story)

    # Assert 1 — redirige avec alerte (set_story n'a pas trouvé l'histoire)
    assert_redirected_to stories_path

    # Assert 2 — l'histoire de Paul existe toujours
    assert Story.find_by(id: paul_story_id),
           "L'histoire de Paul ne devrait pas être supprimée par Marie"
  end
end
