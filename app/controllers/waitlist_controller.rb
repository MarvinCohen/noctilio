class WaitlistController < ApplicationController
  # ============================================================
  # Controller de la liste d'attente pré-lancement
  # ============================================================
  # Reçoit les emails soumis depuis la landing page
  # et les sauvegarde en base de données.
  #
  # Accessible sans être connecté — c'est une page publique
  skip_before_action :authenticate_user!, only: [:create]

  def create
    # Récupère l'email depuis les paramètres du formulaire
    @entry = WaitlistEntry.new(email: params[:email])

    if @entry.save
      # Succès : retourne JSON avec le nouveau compteur d'inscrits
      render json: {
        success: true,
        count: WaitlistEntry.count
      }
    else
      # Échec : retourne les erreurs pour les afficher côté client
      render json: {
        success: false,
        error: @entry.errors.full_messages.first
      }, status: :unprocessable_entity
    end
  end
end
