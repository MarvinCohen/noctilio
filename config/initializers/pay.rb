# ============================================================
# Initializer Pay — configuration de l'intégration Stripe
# ============================================================
# Le gem Pay gère les abonnements Stripe : création du client,
# checkout, webhooks, et mise à jour automatique du statut.
#
# Documentation Pay 7 : https://github.com/pay-rails/pay
# ============================================================

Pay.setup do |config|
  # Nom de l'application affiché dans les emails Pay
  config.business_name = "Noctilio"

  # Email de support affiché dans les emails transactionnels Pay
  config.support_email = ENV.fetch("SUPPORT_EMAIL", "contact@noctilio.fr")

  # Nom du produit par défaut (utilisé dans les receipts Pay)
  config.default_product_name = "Noctilio"

  # Nom du plan par défaut
  config.default_plan_name = "Premium"

  # Pay peut envoyer des emails automatiques (reçus, échecs de paiement)
  # Mettre à false si tu gères toi-même tous les emails
  config.send_emails = true

  # Active uniquement Stripe comme processeur de paiement
  # (pas de Paddle, pas de Braintree)
  config.enabled_processors = [:stripe]
end
