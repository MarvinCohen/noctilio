# Test du FeedbacksController et de l'accès admin aux retours
# Vérifie :
# - GET /avis accessible à tous (connecté ou non)
# - POST /avis crée un retour, rattache l'auteur si connecté, gère le honeypot
# - GET /admin/feedbacks réservé aux admins
require "test_helper"

class FeedbacksControllerTest < ActionDispatch::IntegrationTest
  # ===========================================================
  # HELPER — connexion Devise (même approche que les autres tests controller)
  # ===========================================================
  def sign_in_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password" }
    }
    follow_redirect!
  end

  # ===========================================================
  # SECTION 1 — GET /avis (formulaire public)
  # ===========================================================

  # La page doit s'afficher pour un visiteur NON connecté (skip authenticate_user!)
  # Pourquoi : on veut récolter des retours même de visiteurs sans compte
  test "GET /avis s'affiche pour un visiteur anonyme" do
    get feedback_path
    assert_response :success, "La page /avis devrait être publique (200 sans connexion)"
  end

  # La page doit aussi s'afficher pour un utilisateur connecté
  test "GET /avis s'affiche pour un utilisateur connecté" do
    sign_in_as(users(:marie))
    get feedback_path
    assert_response :success, "La page /avis devrait répondre 200 pour un utilisateur connecté"
  end

  # ===========================================================
  # SECTION 2 — POST /avis (création)
  # ===========================================================

  # Cas nominal anonyme : un retour valide est enregistré et redirige vers la landing
  test "POST /avis crée un retour pour un visiteur anonyme" do
    assert_difference "Feedback.count", 1, "Un retour valide devrait créer un Feedback" do
      post feedback_path, params: {
        feedback: { message: "Super application, bravo !", category: "suggestion", email: "" }
      }
    end
    # Visiteur anonyme → renvoyé vers la landing publique
    assert_redirected_to root_path

    # Le retour est anonyme : pas de user rattaché
    feedback = Feedback.last
    assert_nil feedback.user, "Un retour anonyme ne doit pas avoir de user"
  end

  # Cas connecté : le retour est rattaché à l'utilisateur et redirige vers le dashboard
  test "POST /avis rattache l'utilisateur connecté" do
    user = users(:marie)
    sign_in_as(user)

    assert_difference "Feedback.count", 1 do
      post feedback_path, params: {
        feedback: { message: "Un retour de Marie connectée.", category: "bug" }
      }
    end
    assert_redirected_to dashboard_path, "Un utilisateur connecté est renvoyé vers son dashboard"

    # Le retour doit être rattaché à Marie
    assert_equal user.id, Feedback.last.user_id, "Le retour devrait être rattaché à l'utilisateur connecté"
  end

  # Anti-spam : si le champ honeypot "website" est rempli (comportement de bot),
  # on n'enregistre RIEN mais on fait semblant d'accepter (redirection normale)
  test "POST /avis ignore le retour si le honeypot est rempli" do
    assert_no_difference "Feedback.count", "Un retour avec honeypot rempli ne doit pas être enregistré" do
      post feedback_path, params: {
        website: "http://spam.example", # champ piège rempli par un bot
        feedback: { message: "Message de spam automatisé.", category: "autre" }
      }
    end
    # On redirige quand même normalement (ne pas révéler la détection au bot)
    assert_redirected_to root_path
  end

  # Validation : un message vide réaffiche le formulaire avec une erreur (422)
  test "POST /avis avec message vide réaffiche le formulaire" do
    assert_no_difference "Feedback.count", "Un message vide ne doit pas créer de Feedback" do
      post feedback_path, params: {
        feedback: { message: "", category: "bug" }
      }
    end
    assert_response :unprocessable_entity, "Un formulaire invalide devrait renvoyer 422"
  end

  # ===========================================================
  # SECTION 3 — GET /admin/feedbacks (réservé admin)
  # ===========================================================

  # Un utilisateur non admin ne doit PAS accéder à la liste des retours
  test "GET /admin/feedbacks est refusé pour un non-admin" do
    sign_in_as(users(:marie))
    get admin_feedbacks_path
    assert_redirected_to dashboard_path, "Un non-admin devrait être redirigé"
    assert_equal "Accès non autorisé.", flash[:alert]
  end

  # Un admin doit pouvoir consulter la liste des retours
  test "GET /admin/feedbacks s'affiche pour un admin" do
    sign_in_as(users(:admin_user))
    get admin_feedbacks_path
    assert_response :success, "Un admin devrait pouvoir consulter les retours"
  end

  # Un visiteur anonyme est renvoyé vers la connexion (authenticate_user! global)
  test "GET /admin/feedbacks redirige un visiteur anonyme vers la connexion" do
    get admin_feedbacks_path
    assert_redirected_to new_user_session_path
  end
end
