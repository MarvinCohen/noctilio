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
    # Charge tous les inscrits, du plus récent au plus ancien
    @entries = WaitlistEntry.order(created_at: :desc)

    # Compte total pour l'affichage du résumé
    @total = @entries.count
  end

  private

  # ============================================================
  # Vérifie que l'utilisateur connecté est bien admin
  # Si ce n'est pas le cas, redirige vers le dashboard
  # ============================================================
  def require_admin!
    # Utilise User#admin? qui vérifie la colonne admin en base
    # Pour activer : User.find_by(email: "ton@email.com").update!(admin: true)
    unless current_user.admin?
      redirect_to dashboard_path, alert: "Accès non autorisé."
    end
  end
end
