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

  # Vérifie que les boutons de checkout portent l'attribut de tracking Umami
  # Cas : GET /abonnement avec un compte gratuit (les cartes de prix sont affichées)
  # Pourquoi : Umami suit le clic via data-umami-event="checkout_started" — c'est
  # notre seul moyen de capturer l'intention d'achat avant la redirection Stripe.
  test "GET /abonnement rend les boutons avec data-umami-event checkout_started" do
    sign_in_as(users(:marie))

    get subscription_path

    assert_select "button[data-umami-event=?]", "checkout_started",
                  { count: 2 },
                  "Les deux boutons de checkout doivent porter l'événement checkout_started"
  end

  # Vérifie que le retour de paiement pose l'événement funnel "subscription_activated"
  # Cas : Marie revient de Stripe sur /abonnement/success
  # Pourquoi : c'est la conversion finale du funnel — le layout lira ce flash
  # après la redirection vers le dashboard pour émettre le track Umami.
  test "GET /abonnement/success pose flash[:umami_event] à subscription_activated" do
    sign_in_as(users(:marie))

    get subscription_success_path

    assert_redirected_to dashboard_path
    assert_equal "subscription_activated", flash[:umami_event],
                 "Le retour de paiement doit poser l'événement funnel subscription_activated"
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
  # SECTION 3bis — Toggle Mensuel/Annuel + routage des price IDs
  # ===========================================================

  # Vérifie que la page affiche bien le toggle Mensuel/Annuel (2 onglets)
  # Cas : GET /abonnement avec un compte gratuit (les cartes de prix sont affichées)
  # Pourquoi : le toggle est le point d'entrée de l'offre annuelle (-25% de LTV) ;
  # sans lui, l'utilisateur ne peut pas choisir la période.
  test "GET /abonnement affiche le toggle Mensuel/Annuel" do
    sign_in_as(users(:marie))

    get subscription_path

    # Le conteneur porte le controller Stimulus qui pilote la bascule.
    assert_select "[data-controller=?]", "pricing-toggle"
    # Deux onglets exactement : Mensuel et Annuel.
    assert_select "button[data-pricing-toggle-target=?]", "tab",
                  { count: 2 },
                  "Le toggle doit proposer deux onglets (Mensuel et Annuel)"
  end

  # Vérifie qu'un checkout Essentiel ANNUEL lit bien STRIPE_ESSENTIEL_ANNUAL_PRICE_ID
  # Cas : POST /abonnement/checkout plan=essentiel period=annual, variable annuelle absente
  # Pourquoi : on prouve que la combinaison (essentiel + annual) route vers la
  # bonne variable — si elle manque, ENV.fetch lève KeyError AVANT tout appel réseau.
  test "POST checkout essentiel annuel lit la variable annuelle Essentiel" do
    sign_in_as(users(:marie))

    ancienne_valeur = ENV.delete("STRIPE_ESSENTIEL_ANNUAL_PRICE_ID")

    post subscription_checkout_path, params: { plan: "essentiel", period: "annual" }

    assert_redirected_to subscription_path
    assert_equal "Configuration Stripe manquante. Contacte l'administrateur.",
                 flash[:alert],
                 "Le checkout Essentiel annuel doit lire STRIPE_ESSENTIEL_ANNUAL_PRICE_ID"
  ensure
    ENV["STRIPE_ESSENTIEL_ANNUAL_PRICE_ID"] = ancienne_valeur if ancienne_valeur
  end

  # Vérifie qu'un checkout Premium ANNUEL lit bien STRIPE_PREMIUM_ANNUAL_PRICE_ID
  # Cas : POST /abonnement/checkout plan=premium period=annual, variable annuelle absente
  # Pourquoi : même logique que ci-dessus pour la combinaison (premium + annual).
  test "POST checkout premium annuel lit la variable annuelle Premium" do
    sign_in_as(users(:marie))

    ancienne_valeur = ENV.delete("STRIPE_PREMIUM_ANNUAL_PRICE_ID")

    post subscription_checkout_path, params: { plan: "premium", period: "annual" }

    assert_redirected_to subscription_path
    assert_equal "Configuration Stripe manquante. Contacte l'administrateur.",
                 flash[:alert],
                 "Le checkout Premium annuel doit lire STRIPE_PREMIUM_ANNUAL_PRICE_ID"
  ensure
    ENV["STRIPE_PREMIUM_ANNUAL_PRICE_ID"] = ancienne_valeur if ancienne_valeur
  end

  # Vérifie qu'une période invalide retombe sur le tarif MENSUEL (jamais annuel)
  # Cas : POST plan=essentiel period="n_importe_quoi", variable MENSUELLE absente
  # Pourquoi : checkout_period n'accepte que "monthly"/"annual" ; toute autre valeur
  # doit retomber sur "monthly" (anti-injection). On le prouve : la variable mensuelle
  # manquante lève KeyError, donc c'est bien elle qui a été lue (pas l'annuelle).
  test "POST checkout avec période invalide retombe sur le tarif mensuel" do
    sign_in_as(users(:marie))

    ancienne_valeur = ENV.delete("STRIPE_ESSENTIEL_PRICE_ID")

    post subscription_checkout_path, params: { plan: "essentiel", period: "n_importe_quoi" }

    assert_redirected_to subscription_path
    assert_equal "Configuration Stripe manquante. Contacte l'administrateur.",
                 flash[:alert],
                 "Une période invalide doit retomber sur le prix mensuel (STRIPE_ESSENTIEL_PRICE_ID)"
  ensure
    ENV["STRIPE_ESSENTIEL_PRICE_ID"] = ancienne_valeur if ancienne_valeur
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

  # ===========================================================
  # SECTION 5 — Upgrade Essentiel → Premium (swap_plan)
  # ===========================================================

  # Vérifie que le changement d'offre est protégé pour les visiteurs non connectés
  # Cas : POST /abonnement/changer-offre sans session
  # Pourquoi : on ne doit jamais modifier un abonnement pour un visiteur anonyme
  test "POST /abonnement/changer-offre redirige vers la connexion si non connecté" do
    post subscription_swap_path

    assert_redirected_to new_user_session_path,
                         "Le changement d'offre devrait être inaccessible sans connexion"
  end

  # Vérifie que l'upgrade gère l'absence d'abonnement Essentiel sans planter
  # Cas : un compte gratuit (aucun abonnement Stripe) tente de passer Premium
  # Pourquoi : la garde anti double-abonnement doit bloquer avant tout appel Stripe
  test "POST /abonnement/changer-offre sans abonnement Essentiel affiche le bon message" do
    sign_in_as(users(:marie))

    post subscription_swap_path

    assert_redirected_to subscription_path,
                         "L'upgrade sans abonnement Essentiel devrait revenir sur /abonnement"
    assert_equal "Aucun abonnement Essentiel à faire évoluer.", flash[:alert]
  end
end
