class SubscriptionsController < ApplicationController
  # ============================================================
  # Controller des abonnements Stripe
  # ============================================================
  # Gère la page de tarification et le lancement du paiement Stripe Checkout

  # GET /abonnement — page de tarification
  def index
    # Vérifie si l'utilisateur a déjà un abonnement actif
    @is_premium = current_user.premium?

    # Histoires utilisées ce mois (pour montrer la limite atteinte)
    @stories_this_month = current_user.stories_this_month
  end

  # POST /abonnement/checkout — crée une session Stripe Checkout
  # Redirige l'utilisateur vers la page de paiement Stripe
  def checkout
    # Crée une session de paiement Stripe via le gem Pay
    # Le gem Pay gère automatiquement la création du client Stripe
    checkout_session = current_user.payment_processor.checkout(
      mode: "subscription",
      line_items: [{
        price: ENV.fetch("STRIPE_PREMIUM_PRICE_ID"),   # ID du prix dans Stripe Dashboard
        quantity: 1
      }],
      success_url: dashboard_url + "?subscription=success",
      cancel_url:  subscription_url
    )

    # Redirige vers la page Stripe Checkout
    redirect_to checkout_session.url, allow_other_host: true
  rescue Pay::Error => e
    redirect_to subscription_path, alert: "Erreur lors de la création du paiement : #{e.message}"
  end
end
