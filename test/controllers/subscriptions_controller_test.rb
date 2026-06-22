# Test du SubscriptionsController
# Ce fichier vérifie la protection des pages d'abonnement et le comportement
# des actions Stripe dans les cas qui NE nécessitent PAS d'appel réseau réel
# (configuration manquante, absence d'abonnement). On ne teste pas le paiement
# Stripe lui-même (API externe) — uniquement la logique de garde côté serveur,
# qui est ce qui protège réellement le chiffre d'affaires.
require "test_helper"

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest

  # Connecte un utilisateur via le formulaire Devise (comme un vrai login)
  # Le mot de passe "password" correspond à l'encrypted_password des fixtures.
  def sign_in_as(user)
    post user_session_path, params: {
      user: { email: user.email, password: "password" }
    }
    follow_redirect!
  end

  # ===========================================================
  # SECTION 1 — Protection (authentification obligatoire)
  # ===========================================================

  # Vérifie qu'un visiteur non connecté ne peut pas voir la page d'abonnement
  # Cas : GET /abonnement sans session
  # Pourquoi : authenticate_user! dans ApplicationController protège toute l'app
  test "GET /abonnement redirige vers la connexion si non connecté" do
    get subscription_path

    assert_redirected_to new_user_session_path,
                         "Un visiteur non connecté devrait être redirigé vers la connexion"
  end

  # Vérifie que le checkout est protégé pour les visiteurs non connectés
  # Cas : POST /abonnement/checkout sans session
  # Pourquoi : on ne doit jamais lancer un paiement pour un visiteur anonyme
  test "POST /abonnement/checkout redirige vers la connexion si non connecté" do
    post subscription_checkout_path

    assert_redirected_to new_user_session_path,
                         "Le checkout devrait être inaccessible sans connexion"
  end

  # ===========================================================
  # SECTION 2 — Page de tarification (index)
  # ===========================================================

  # Vérifie que la page d'abonnement s'affiche pour un utilisateur connecté
  # Cas : GET /abonnement avec un compte gratuit (Marie)
  # Pourquoi : c'est la vitrine premium — elle doit toujours se charger
  test "GET /abonnement s'affiche pour un utilisateur connecté" do
    sign_in_as(users(:marie))

    get subscription_path

    assert_response :success,
                    "La page de tarification devrait s'afficher pour un connecté"
  end

  # ===========================================================
  # SECTION 3 — Checkout : configuration Stripe manquante
  # ===========================================================

  # Vérifie que le checkout échoue proprement si STRIPE_PREMIUM_PRICE_ID est absent
  # Cas : variable d'env non définie → ENV.fetch lève KeyError → rescue dédié
  # Pourquoi : sans cette garde, une config manquante planterait avec une 500
  test "POST /abonnement/checkout gère l'absence de STRIPE_PREMIUM_PRICE_ID" do
    sign_in_as(users(:marie))

    # On s'assure que la variable est absente le temps du test, puis on la restaure.
    ancienne_valeur = ENV.delete("STRIPE_PREMIUM_PRICE_ID")

    post subscription_checkout_path

    # ENV.fetch lève KeyError AVANT tout appel réseau → rescue KeyError
    assert_redirected_to subscription_path,
                         "Un checkout sans config Stripe devrait revenir sur la page d'abonnement"
    assert_equal "Configuration Stripe manquante. Contacte l'administrateur.",
                 flash[:alert]
  ensure
    # Restaure l'éventuelle valeur d'origine pour ne pas polluer les autres tests
    ENV["STRIPE_PREMIUM_PRICE_ID"] = ancienne_valeur if ancienne_valeur
  end

  # ===========================================================
  # SECTION 4 — Annulation / réactivation sans abonnement actif
  # ===========================================================

  # Vérifie que l'annulation gère l'absence d'abonnement sans planter
  # Cas : un compte gratuit (aucun abonnement Stripe) tente d'annuler
  # Pourquoi : on doit toujours revenir sur la page d'abonnement avec un message
  test "POST /abonnement/cancel sans abonnement revient sur la page d'abonnement" do
    sign_in_as(users(:marie))

    post subscription_cancel_path

    assert_redirected_to subscription_path,
                         "L'annulation sans abonnement actif devrait revenir sur /abonnement"
  end

  # Vérifie que la réactivation gère l'absence de résiliation programmée
  # Cas : un compte gratuit tente de réactiver alors qu'il n'a rien à réactiver
  # Pourquoi : seul un abonnement en période de grâce peut être réactivé
  test "POST /abonnement/reactiver sans résiliation affiche le bon message" do
    sign_in_as(users(:marie))

    post subscription_resume_path

    assert_redirected_to subscription_path
    assert_equal "Aucune résiliation à annuler.", flash[:alert]
  end
end
