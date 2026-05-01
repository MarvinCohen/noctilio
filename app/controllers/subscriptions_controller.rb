class SubscriptionsController < ApplicationController
  # ============================================================
  # Controller des abonnements Stripe
  # ============================================================
  # Gère la page de tarification, le lancement du paiement via
  # Stripe Checkout, le retour après paiement, et l'annulation.
  #
  # Flux complet :
  #   1. index     → affiche les offres (gratuit / premium)
  #   2. checkout  → crée une Stripe Checkout Session et redirige
  #   3. success   → Stripe redirige ici après paiement réussi
  #   4. cancel    → annule l'abonnement (résilie à fin de période)
  # ============================================================

  # GET /abonnement — page de tarification
  def index
    # Indique à la vue si l'utilisateur est déjà premium
    @is_premium = current_user.premium?

    # Nombre d'histoires créées ce mois-ci (pour afficher la jauge gratuite)
    @stories_this_month = current_user.stories_this_month
  end

  # POST /abonnement/checkout — lance le paiement Stripe
  def checkout
    # Stripe nécessite un "processor" Pay associé à cet utilisateur.
    # set_payment_processor crée ou récupère le client Stripe pour l'user.
    current_user.set_payment_processor :stripe

    # Crée une Stripe Checkout Session hébergée par Stripe.
    # L'utilisateur saisit sa CB directement sur la page Stripe (sécurisé PCI).
    #
    # mode: "subscription" → abonnement récurrent (pas paiement unique)
    # line_items           → le produit à acheter (price_id depuis l'env)
    # success_url          → où Stripe redirige après paiement réussi
    # cancel_url           → où Stripe redirige si l'utilisateur abandonne
    @checkout_session = current_user.payment_processor.checkout(
      mode: "subscription",
      line_items: [{
        price:    ENV.fetch("STRIPE_PREMIUM_PRICE_ID"),
        quantity: 1
      }],
      success_url: subscription_success_url(session_id: "{CHECKOUT_SESSION_ID}"),
      cancel_url:  subscription_url
    )

    # Redirige vers la page de paiement Stripe (domaine externe)
    # allow_other_host: true est obligatoire pour les redirections vers Stripe
    redirect_to @checkout_session.url, allow_other_host: true

  rescue KeyError
    # STRIPE_PREMIUM_PRICE_ID n'est pas défini dans les variables d'environnement
    redirect_to subscription_path,
      alert: "Configuration Stripe manquante. Contacte l'administrateur."

  rescue => e
    # Erreur inattendue (API Stripe down, clé invalide, etc.)
    Rails.logger.error "[Stripe] Erreur checkout : #{e.message}"
    redirect_to subscription_path,
      alert: "Une erreur est survenue lors du paiement. Réessaie dans quelques instants."
  end

  # GET /abonnement/success?session_id=... — retour après paiement réussi
  def success
    # Pay met à jour automatiquement l'abonnement via le webhook Stripe.
    # Cette page confirme simplement à l'utilisateur que tout s'est bien passé.
    # On recharge l'état premium depuis la base (le webhook a pu arriver entre-temps).
    @is_premium = current_user.premium?

    # Redirige vers le dashboard avec un message de confirmation
    redirect_to dashboard_path,
      notice: "Bienvenue dans Noctilio Premium ! Profite d'histoires illimitées. ✨"
  end

  # POST /abonnement/cancel — annule l'abonnement en cours
  def cancel
    # Récupère l'abonnement Stripe actif de l'utilisateur via Pay
    subscription = current_user.payment_processor.subscription

    if subscription.present?
      # cancel_now! résilie immédiatement.
      # cancel     résilie à la fin de la période payée (plus sympa pour l'utilisateur).
      # On choisit cancel : l'utilisateur garde l'accès premium jusqu'à l'échéance.
      subscription.cancel

      redirect_to subscription_path,
        notice: "Ton abonnement sera résilié à la fin de la période en cours."
    else
      redirect_to subscription_path,
        alert: "Aucun abonnement actif trouvé."
    end

  rescue => e
    Rails.logger.error "[Stripe] Erreur annulation : #{e.message}"
    redirect_to subscription_path,
      alert: "Impossible d'annuler l'abonnement. Contacte le support."
  end
end
