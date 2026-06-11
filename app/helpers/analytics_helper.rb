# ============================================================
# AnalyticsHelper — décide si le tracking analytics doit s'activer
# ============================================================
# Utilisé par le partial shared/_analytics.html.erb pour insérer (ou non)
# le script Umami Cloud dans le <head> des layouts.
module AnalyticsHelper
  # ============================================================
  # umami_enabled? — true si le script de tracking Umami doit être rendu
  # ============================================================
  # Deux conditions cumulatives doivent être réunies :
  #   1. ENV["UMAMI_WEBSITE_ID"] est défini
  #      → cette variable n'existe que sur Railway (prod), donc en dev et en test
  #        elle est absente : l'analytics est automatiquement désactivé localement
  #   2. L'utilisateur connecté n'est PAS admin
  #      → évite de polluer les statistiques avec le mode test de Marvin
  #        (un visiteur anonyme sur la landing a current_user == nil → tracké)
  def umami_enabled?
    # Sans identifiant de site, aucun tracking possible
    return false if ENV["UMAMI_WEBSITE_ID"].blank?

    # respond_to? : garde défensive — current_user n'est fourni par Devise que
    # dans un contexte de vue. Évite une erreur si le helper est appelé ailleurs.
    return false if respond_to?(:current_user) && current_user&.admin?

    true
  end
end
