# ============================================================
# FeedbacksController — page publique de retours utilisateurs
# ============================================================
# Permet à n'importe quel visiteur (connecté ou non) de laisser un retour.
# GET  /avis  → affiche le formulaire
# POST /avis  → enregistre le retour puis remercie l'utilisateur
class FeedbacksController < ApplicationController
  # La page de retours est PUBLIQUE : on désactive l'authentification Devise
  # imposée globalement par ApplicationController (comme les pages légales).
  skip_before_action :authenticate_user!

  # Affiche le formulaire de retour
  def new
    # Objet vide pour le form_with — on pré-remplit l'email si l'utilisateur
    # est connecté (évite qu'il le retape, et on saura qui a écrit)
    @feedback = Feedback.new(email: current_user&.email)
  end

  # Enregistre le retour envoyé via le formulaire
  def create
    # Anti-spam : champ "honeypot" caché en CSS, invisible pour un humain.
    # Un bot le remplit automatiquement → si présent, on fait semblant d'accepter
    # (redirection normale) pour ne pas signaler au bot qu'il est détecté.
    if params[:website].present?
      redirect_to dashboard_or_root, notice: "Merci pour votre retour !"
      return
    end

    # Construit le retour à partir des champs autorisés (strong parameters)
    @feedback = Feedback.new(feedback_params)
    # Rattache l'utilisateur connecté (nil si visiteur anonyme)
    @feedback.user = current_user
    # Mémorise la page d'origine pour le contexte (utile pour débuguer un bug signalé)
    @feedback.page_url = request.referer

    if @feedback.save
      # Succès : on remercie et on renvoie vers l'accueil adapté (dashboard ou landing)
      redirect_to dashboard_or_root, notice: "Merci pour votre retour, il nous aide à améliorer Noctilio !"
    else
      # Échec de validation : on réaffiche le formulaire avec les erreurs
      # status 422 = convention Rails/Turbo pour un formulaire invalide
      render :new, status: :unprocessable_entity
    end
  end

  private

  # Champs autorisés depuis le formulaire — message, email et catégorie.
  # page_url et user_id sont fixés côté serveur (jamais via le formulaire).
  def feedback_params
    params.require(:feedback).permit(:message, :email, :category)
  end

  # Renvoie vers le dashboard si connecté, sinon vers la landing publique.
  # Un visiteur anonyme ne peut pas accéder au dashboard (protégé par Devise).
  def dashboard_or_root
    user_signed_in? ? dashboard_path : root_path
  end
end
