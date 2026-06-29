class BadgesController < ApplicationController
  # ============================================================
  # Controller des badges — accusé de notification
  # ============================================================
  # Sert uniquement à enregistrer que les badges en attente ont bien été
  # "fêtés" à l'écran (notification + confettis), pour ne pas les re-notifier.
  # L'authentification est assurée par le before_action global d'ApplicationController.

  # POST /badges/vus
  # Appelé en arrière-plan (fetch) par le Stimulus badge_check après affichage.
  def mark_seen
    # Bascule tous les badges non notifiés de l'utilisateur à notified: true.
    # Logique métier déléguée au modèle (Fat Model / Skinny Controller).
    current_user.mark_badges_notified!

    # Réponse minimale : le front n'a besoin d'aucun contenu, juste d'un 200 OK.
    head :ok
  end
end
