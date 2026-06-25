# ============================================================
# PushSubscriptionsController — enregistre / supprime un abonnement push
# ============================================================
# Appelé par le Stimulus push_controller :
#   - POST   quand l'utilisateur active les rappels (le navigateur a accepté)
#   - DELETE quand il les désactive
# Toujours scopé sur current_user : on ne touche jamais l'abonnement d'un autre.
# ============================================================
class PushSubscriptionsController < ApplicationController
  # Réservé aux utilisateurs connectés (un abonnement appartient à un compte)
  before_action :authenticate_user!

  # POST /push_subscriptions
  # Enregistre l'abonnement renvoyé par l'API PushManager du navigateur.
  def create
    # find_or_initialize_by sur l'endpoint : si le navigateur réémet le même
    # abonnement, on le met à jour au lieu de créer un doublon.
    subscription = current_user.push_subscriptions.find_or_initialize_by(
      endpoint: subscription_params[:endpoint]
    )
    subscription.p256dh_key = subscription_params[:p256dh_key]
    subscription.auth_key   = subscription_params[:auth_key]

    if subscription.save
      head :ok
    else
      # 422 : données d'abonnement incomplètes/invalides
      head :unprocessable_entity
    end
  end

  # DELETE /push_subscriptions
  # Supprime l'abonnement de cet appareil (identifié par son endpoint).
  def destroy
    current_user.push_subscriptions
                .find_by(endpoint: params[:endpoint])
                &.destroy
    head :no_content
  end

  private

  # Mass assignment protégé : on n'autorise que les 3 champs de l'abonnement.
  def subscription_params
    params.require(:subscription).permit(:endpoint, :p256dh_key, :auth_key)
  end
end
