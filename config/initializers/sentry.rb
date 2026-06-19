# ============================================================
# Sentry — monitoring des erreurs en production
# ============================================================
# Sentry capture automatiquement les exceptions non gérées (contrôleurs, jobs
# Solid Queue, etc.) et les remonte sur le tableau de bord Sentry pour être
# alerté des bugs réels rencontrés par les utilisateurs.
#
# ACTIVATION : on ne configure Sentry QUE si la variable d'environnement
# SENTRY_DSN est définie (le DSN vient du compte Sentry, à mettre sur Railway).
# Tant qu'elle est absente (dev, test, ou prod non configurée), ce bloc est
# ignoré → Sentry reste inerte et n'envoie rien. Même logique que UMAMI_WEBSITE_ID.
if ENV["SENTRY_DSN"].present?
  Sentry.init do |config|
    # Adresse du projet Sentry — fournie par le compte Sentry, jamais codée en dur
    config.dsn = ENV["SENTRY_DSN"]

    # Nom de l'environnement affiché dans Sentry (production, staging…) pour
    # distinguer les erreurs selon leur provenance.
    config.environment = Rails.env

    # On ne remonte les erreurs QUE depuis la production : pas de bruit depuis le dev.
    config.enabled_environments = %w[production]

    # Échantillonnage des traces de performance (0.0 = aucune, 1.0 = toutes).
    # 10 % suffit à surveiller les temps de réponse sans saturer le quota gratuit.
    config.traces_sample_rate = 0.1

    # Ne PAS envoyer les paramètres de requête contenant des données sensibles
    # (mots de passe, etc.) — Sentry les filtre déjà, on garde le réglage par défaut.
    config.send_default_pii = false
  end
end
