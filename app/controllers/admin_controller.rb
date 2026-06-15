# ============================================================
# AdminController — pages d'administration privées
# Accessible UNIQUEMENT par le compte marvincohen95@gmail.com
# Tout autre utilisateur est redirigé vers le dashboard
# ============================================================
class AdminController < ApplicationController
  # Vérifie l'accès admin avant chaque action de ce controller
  before_action :require_admin!

  # ============================================================
  # GET /admin/waitlist
  # Affiche tous les emails inscrits sur la liste d'attente
  # triés du plus récent au plus ancien
  # ============================================================
  def waitlist
    # Charge tous les inscrits en mémoire en une seule requête SQL
    # .to_a force l'exécution immédiate — évite 3 requêtes séparées (count, any?, each)
    @entries = WaitlistEntry.order(created_at: :desc).limit(500).to_a

    # Calcul en Ruby sur le tableau déjà chargé — pas de requête SQL supplémentaire
    @total = @entries.size
  end

  # ============================================================
  # GET /admin/feedbacks
  # Affiche tous les retours utilisateurs, du plus récent au plus ancien
  # ============================================================
  def feedbacks
    # includes(:user) précharge l'auteur en une requête → évite le N+1 dans la vue
    # (sinon une requête SQL par retour pour afficher le nom de l'auteur)
    @feedbacks = Feedback.includes(:user).order(created_at: :desc).limit(500).to_a

    # Total affiché en tête de page — calcul en Ruby sur le tableau déjà chargé
    @total = @feedbacks.size
  end

  private

  # ============================================================
  # Vérifie que l'utilisateur connecté est bien admin
  # Si ce n'est pas le cas, redirige vers le dashboard
  # ============================================================
  def require_admin!
    # Utilise User#admin? qui vérifie la colonne admin en base
    # Pour activer : User.find_by(email: "ton@email.com").update!(admin: true)
    return if current_user.admin?

    redirect_to dashboard_path, alert: "Accès non autorisé."
  end
end
