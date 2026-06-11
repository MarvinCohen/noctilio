# Test du SharedStoriesController
# Vérifie le partage public d'une histoire en lecture seule :
# - un visiteur NON connecté peut lire une histoire via un lien signé valide
# - un token invalide/falsifié renvoie 404 (pas de fuite, pas d'accès)
# - une histoire non terminée n'est pas accessible publiquement
require "test_helper"

class SharedStoriesControllerTest < ActionDispatch::IntegrationTest

  # ===========================================================
  # Accès public avec un token valide
  # ===========================================================

  # Vérifie qu'un visiteur anonyme accède à l'histoire via son lien signé
  # Pourquoi : tout l'intérêt du partage est de NE PAS exiger de compte
  test "GET /histoire/:token affiche l'histoire sans être connecté" do
    # Arrange — une histoire terminée + son token de partage
    story = stories(:completed_saved)

    # Act — accès SANS connexion préalable
    get shared_story_path(token: story.share_token)

    # Assert — page accessible (200) et contenu présent
    assert_response :success
    assert_select "h1.shared-story__title", text: story.title
  end

  # ===========================================================
  # Token invalide → 404
  # ===========================================================

  # Vérifie qu'un token falsifié ne donne accès à rien
  # Pourquoi : sécurité — on ne doit pas pouvoir deviner/forger un lien
  test "GET /histoire/:token renvoie 404 pour un token invalide" do
    # Act — token qui n'est pas une signature valide
    get shared_story_path(token: "token-bidon")

    # Assert — 404 Not Found
    assert_response :not_found
  end

  # ===========================================================
  # Histoire non terminée → 404
  # ===========================================================

  # Vérifie qu'on ne peut pas partager une histoire encore en génération
  # Pourquoi : un lien public ne doit pointer que vers une histoire lisible
  test "GET /histoire/:token renvoie 404 pour une histoire non terminée" do
    # Arrange — histoire en cours de génération (status pending)
    story = stories(:pending_story)

    # Act — token techniquement valide mais histoire non terminée
    get shared_story_path(token: story.share_token)

    # Assert — refusé
    assert_response :not_found
  end
end
