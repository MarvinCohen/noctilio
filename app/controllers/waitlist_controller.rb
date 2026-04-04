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
      # Succès : retourne JSON avec le compteur affiché
      # On utilise max(count, 247) pour rester cohérent avec l'affichage initial
      # qui part de 247 — sinon l'animation recule (ex: 247 → 6) et ne bouge pas
      # Cumul waitlist + users Devise — même logique que PagesController#home
      render json: {
        success: true,
        count: [WaitlistEntry.count + User.count, 247].max
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
