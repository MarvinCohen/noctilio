class SharedStoriesController < ApplicationController
  # ============================================================
  # Controller des histoires partagées publiquement (lecture seule)
  # ============================================================
  # Affiche une histoire à un visiteur NON connecté, à partir d'un lien signé.
  # Objectif : acquisition — un parent partage une histoire, le destinataire
  # la lit puis est invité à créer son propre compte Noctilio.

  # Cette page est publique : on désactive l'obligation de connexion héritée
  # d'ApplicationController (before_action :authenticate_user!).
  skip_before_action :authenticate_user!

  # On réutilise le layout "landing" (autonome, sans navbar/sidebar de l'app)
  # plutôt que le layout application qui suppose un utilisateur connecté.
  layout "landing"

  # GET /histoire/:token — affiche l'histoire correspondant au token signé
  def show
    # find_by_share_token renvoie nil si le token est invalide/falsifié
    # ou si l'histoire n'est pas terminée (voir Story.find_by_share_token)
    @story = Story.find_by_share_token(params[:token])

    # Token invalide ou histoire introuvable → 404 (pas de fuite d'information)
    return head :not_found if @story.nil?
  end
end
