# ============================================================
# LocaleController — changement de langue de l'interface (i18n)
# ============================================================
# Reçoit le choix de langue depuis le sélecteur (shared/_locale_switcher),
# le valide, le mémorise (session + compte si connecté) puis renvoie
# l'utilisateur sur la page d'origine DANS LA NOUVELLE LANGUE.
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
    else
      # Langue invalide : on retombe sur le français pour le calcul de redirection.
      requested = I18n.default_locale
    end

    # Renvoie l'utilisateur sur la page d'origine, mais avec le préfixe d'URL
    # adapté à la nouvelle langue. C'est INDISPENSABLE pour les pages publiques :
    # leur langue est déterminée par le préfixe d'URL (/es/blog…), prioritaire sur
    # la session. Sans cette réécriture, un retour sur /es/blog réafficherait la
    # page en espagnol même après avoir choisi l'allemand.
    redirect_to localized_redirect_path(requested)
  end

  private

  # Calcule le chemin de redirection après un changement de langue.
  # - Récupère le chemin de la page d'origine (referer), accueil par défaut.
  # - Retire un éventuel préfixe de langue déjà présent (/en, /es, /de, /it, /pt).
  # - FR (langue par défaut) : aucun préfixe -> on renvoie le chemin nu.
  # - Autres langues : on ajoute le préfixe SEULEMENT si la page est une page
  #   publique (route reconnue sous le scope "(:locale)"). Pour l'app privée
  #   (sans préfixe), on garde le chemin nu : la langue y est gérée par la session.
  def localized_redirect_path(locale)
    # Chemin d'origine ; on n'utilise que le PATH (pas l'hôte) -> pas d'open redirect.
    referer = request.referer
    path = referer.present? ? URI.parse(referer).path : root_path

    # Retire le préfixe de langue éventuel en tête de chemin (ex: /es/blog -> /blog).
    bare = path.sub(%r{\A/(en|es|de|it|pt)(?=/|\z)}, "")
    # Un chemin vide (ex: ancien "/es" -> "") redevient la racine.
    bare = "/" if bare.blank?

    # Français : pas de préfixe d'URL (langue canonique) -> chemin nu.
    return bare if locale == I18n.default_locale

    # Pour les autres langues : on construit le chemin préfixé candidat…
    candidate = "/#{locale}#{bare == '/' ? '' : bare}"

    # …et on vérifie qu'il correspond bien à une route publique (avec :locale).
    # recognize_path lève une exception si le chemin n'est pas routable
    # (cas d'une page privée : /de/home n'existe pas) -> on retombe alors sur
    # le chemin nu, la session prenant le relais pour la langue.
    recognized = begin
      Rails.application.routes.recognize_path(candidate)
    rescue ActionController::RoutingError
      nil
    end

    recognized && recognized[:locale] ? candidate : bare
  end
end
