class SubscriptionsController < ApplicationController
  # ============================================================
  # Controller des abonnements
  # ============================================================
  # Stripe sera configuré plus tard.
  # Pour l'instant on affiche juste une page "coming soon".

  # GET /abonnement — page de tarification
  def index
    @is_premium       = current_user.premium?
    @stories_this_month = current_user.stories_this_month
  end

  # POST /abonnement/checkout — sera activé quand Stripe sera configuré
  def checkout
    redirect_to subscription_path, alert: "Le paiement sera disponible prochainement !"
  end
end
