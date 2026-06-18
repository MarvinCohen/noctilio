# ============================================================
# LocaleController — changement de langue de l'interface (i18n)
# ============================================================
# Reçoit le choix de langue depuis le sélecteur (shared/_locale_switcher),
# le valide, le mémorise (session + compte si connecté) puis renvoie
# l'utilisateur sur la page d'origine.
class LocaleController < ApplicationController
  # Le sélecteur peut aussi apparaître sur des pages publiques (visiteur non
  # connecté) : on autorise donc l'accès sans authentification.
  skip_before_action :authenticate_user!

  # POST /langue
  # Paramètre attendu : locale (ex: "en", "es"…)
  def update
    # Normalise en symbole pour le comparer à la liste des langues disponibles.
    requested = params[:locale].to_s.to_sym

    # On n'enregistre que si la langue demandée est réellement supportée.
    # (sécurité : empêche d'injecter une locale arbitraire)
    if I18n.available_locales.include?(requested)
      # Mémorise le choix pour les requêtes suivantes (visiteurs + connectés).
      session[:locale] = requested

      # Si l'utilisateur est connecté, on persiste aussi la préférence sur son
      # compte pour la retrouver depuis n'importe quel appareil.
      current_user.update(locale: requested) if user_signed_in?
    end

    # Renvoie l'utilisateur sur la page d'où il vient (fallback : accueil).
    redirect_back fallback_location: root_path
  end
end
