module Webhooks
  class StripeController < ApplicationController
    # ============================================================
    # Controller des webhooks Stripe
    # ============================================================
    # Stripe envoie des événements POST à cette URL pour nous informer
    # des changements d'abonnement (paiement réussi, annulation, etc.)
    #
    # Le gem Pay gère automatiquement les webhooks Stripe.
    # Ce controller délègue donc au handler de Pay.

    # Stripe n'envoie pas de token CSRF — on doit désactiver la protection
    # La sécurité est assurée par la vérification de la signature Stripe
    skip_before_action :verify_authenticity_token

    # Stripe n'envoie pas de header d'authentification utilisateur
    skip_before_action :authenticate_user!

    # POST /webhooks/stripe — reçoit les événements Stripe
    def create
      # Délègue le traitement du webhook au gem Pay
      # Pay vérifie la signature Stripe et met à jour les abonnements automatiquement
      Pay::Webhooks::StripeController.new.create(request)
    end
  end
end
