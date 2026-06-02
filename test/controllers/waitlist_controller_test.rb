# Test du WaitlistController
# Ce fichier vérifie que l'inscription sur la liste d'attente fonctionne :
# - Email valide → succès JSON avec le compteur
# - Email invalide ou doublon → erreur JSON
# - Accessible sans être connecté (page publique)
require "test_helper"

class WaitlistControllerTest < ActionDispatch::IntegrationTest

  # ===========================================================
  # SECTION 1 — Inscription réussie
  # ===========================================================

  # Vérifie qu'un email valide est sauvegardé et retourne le JSON de succès
  # Cas : email valide, pas encore inscrit
  # Pourquoi : c'est le flux principal de la landing page — doit fonctionner sans connexion
  test "POST /waitlist avec un email valide retourne success: true" do
    # Arrange — un email qui n'existe pas encore en base
    count_before = WaitlistEntry.count

    # Act — accessible sans être connecté (skip_before_action dans le controller)
    post waitlist_path, params: { email: "nouveau@test.com" },
                        as: :json

    # Assert 1 — réponse 200 OK
    assert_response :success,
                    "Une inscription valide devrait retourner 200"

    # Assert 2 — JSON avec success: true
    body = JSON.parse(response.body)
    assert body["success"], "La réponse JSON devrait contenir success: true"

    # Assert 3 — le compteur est retourné (au moins 247 selon la logique du controller)
    assert body["count"] >= 247, "Le compteur retourné devrait être >= 247"

    # Assert 4 — un enregistrement a bien été créé en base
    assert_equal count_before + 1, WaitlistEntry.count,
                 "Un WaitlistEntry devrait avoir été créé"
  end

  # ===========================================================
  # SECTION 2 — Inscription avec email invalide
  # ===========================================================

  # Vérifie qu'un email invalide retourne une erreur JSON
  # Cas : email mal formaté (sans @)
  # Pourquoi : la validation format: { with: URI::MailTo::EMAIL_REGEXP } doit bloquer
  test "POST /waitlist avec un email invalide retourne success: false" do
    # Arrange
    count_before = WaitlistEntry.count

    # Act — email sans @
    post waitlist_path, params: { email: "pas_un_email" },
                        as: :json

    # Assert 1 — réponse 422 Unprocessable Entity
    assert_response :unprocessable_entity,
                    "Un email invalide devrait retourner 422"

    # Assert 2 — JSON avec success: false
    body = JSON.parse(response.body)
    assert_not body["success"], "La réponse JSON devrait contenir success: false"
    assert body["error"].present?, "Un message d'erreur devrait être présent dans la réponse"

    # Assert 3 — aucun enregistrement créé
    assert_equal count_before, WaitlistEntry.count,
                 "Aucun WaitlistEntry ne devrait être créé avec un email invalide"
  end

  # ===========================================================
  # SECTION 3 — Email en doublon
  # ===========================================================

  # Vérifie qu'un email déjà inscrit retourne une erreur
  # Cas : même email soumis deux fois
  # Pourquoi : validates uniqueness: true sur WaitlistEntry — un email ne peut s'inscrire qu'une fois
  test "POST /waitlist avec un email en doublon retourne success: false" do
    # Arrange — crée d'abord l'entrée initiale
    WaitlistEntry.create!(email: "doublon@test.com")
    count_before = WaitlistEntry.count

    # Act — essaie d'inscrire le même email
    post waitlist_path, params: { email: "doublon@test.com" },
                        as: :json

    # Assert 1 — réponse 422
    assert_response :unprocessable_entity,
                    "Un email en doublon devrait retourner 422"

    # Assert 2 — JSON avec success: false
    body = JSON.parse(response.body)
    assert_not body["success"], "La réponse JSON devrait contenir success: false pour un doublon"

    # Assert 3 — pas de nouvel enregistrement
    assert_equal count_before, WaitlistEntry.count,
                 "Aucun WaitlistEntry en doublon ne devrait être créé"
  end

  # ===========================================================
  # SECTION 4 — Accès public
  # ===========================================================

  # Vérifie que le endpoint est accessible sans être connecté
  # Cas : visiteur anonyme sur la landing page
  # Pourquoi : skip_before_action :authenticate_user!, only: [:create] dans le controller
  test "POST /waitlist est accessible sans être connecté" do
    # Act — pas de sign_in, requête directe
    post waitlist_path, params: { email: "visiteur@test.com" },
                        as: :json

    # Assert — pas de redirection vers la connexion
    assert_not_equal 302, response.status,
                     "Le endpoint waitlist ne devrait pas rediriger vers la connexion"
    assert_response :success,
                    "Le endpoint waitlist devrait être accessible sans authentification"
  end
end
