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
      # already_subscribed : true si l'échec vient de l'unicité de l'email
      # (l'email est déjà en base). errors.details expose le type d'erreur (:taken)
      # de façon fiable, sans dépendre du texte du message.
      already_subscribed = @entry.errors.details[:email].any? { |e| e[:error] == :taken }

      # Échec : retourne les erreurs pour les afficher côté client
      render json: {
        success: false,
        already_subscribed: already_subscribed,
        error: @entry.errors.full_messages.first
      }, status: :unprocessable_entity
    end
  end
end
