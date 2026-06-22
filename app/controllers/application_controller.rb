class ApplicationController < ActionController::Base
  # ============================================================
  # Redirection www — noctilio-app.fr → www.noctilio-app.fr (301)
  # Les deux domaines sont actifs sur Railway, on canonicalise sur www
  # avant_action en premier pour que ça s'applique à toutes les requêtes
  # ============================================================
  before_action :redirect_to_www

  # ============================================================
  # Langue de l'interface (i18n) — multilingue
  # ============================================================
  # around_action : enveloppe TOUTE l'action dans I18n.with_locale.
  # Avantage par rapport à un before_action : la langue est appliquée pendant
  # le rendu PUIS remise à son état précédent une fois la requête terminée,
  # ce qui évite qu'une locale « fuite » d'une requête à la suivante (les
  # serveurs Rails réutilisent les threads entre les requêtes).
  # Déclaré avant authenticate_user! pour que même la page de connexion et
  # les messages de redirection soient affichés dans la bonne langue.
  around_action :switch_locale

  # ============================================================
  # Authentification — toutes les pages nécessitent une connexion
  # sauf celles qui utilisent skip_before_action
  # ============================================================
  before_action :authenticate_user!

  # ============================================================
  # Redirection après connexion Devise
  # ============================================================
  # Par défaut Devise redirige vers root_path après connexion.
  # On surcharge cette méthode pour rediriger vers le dashboard.
  def after_sign_in_path_for(_resource)
    dashboard_path
  end

  # ============================================================
  # default_url_options — conserve la langue dans les URLs générées
  # ============================================================
  # Rails appelle cette méthode à chaque génération d'URL (link_to, *_path…).
  # On y injecte la locale courante pour que la navigation reste dans la même
  # langue (ex : depuis /en/blog, le lien vers les CGU pointe vers /en/cgu).
  # On renvoie nil quand la langue est le français (langue par défaut) : ainsi
  # le FR n'a jamais de préfixe /fr/ dans ses URLs (cohérent avec la contrainte
  # de routing qui exclut "fr"). Pour les pages hors scope "(:locale)", Rails
  # ignore simplement ce paramètre (il n'apparaît pas dans l'URL).
  def default_url_options
    { locale: (I18n.locale == I18n.default_locale ? nil : I18n.locale) }
  end

  private

  # Détermine la langue de la requête puis exécute l'action dans cette langue.
  # &action est le bloc qui représente l'exécution de l'action du controller.
  def switch_locale(&action)
    # Résolution par ordre de priorité décroissante :
    #   1. paramètre ?locale= dans l'URL (choix explicite, ex: via le sélecteur)
    #   2. langue déjà mémorisée dans la session (choix précédent)
    #   3. préférence enregistrée sur le compte connecté
    #   4. langue du navigateur (en-tête Accept-Language)
    #   5. langue par défaut de l'application (FR)
    requested = params[:locale] ||
                session[:locale] ||
                current_user&.locale ||
                locale_from_browser ||
                I18n.default_locale

    # Normalise en symbole (les available_locales sont des symboles : :fr, :en…)
    locale = requested.to_sym

    # Sécurité : on refuse toute langue non déclarée dans available_locales
    # (ex: ?locale=xx) et on retombe sur le français.
    locale = I18n.default_locale unless I18n.available_locales.include?(locale)

    # Mémorise le choix en session pour qu'il persiste sur les requêtes suivantes,
    # aussi bien pour les visiteurs que pour les comptes connectés.
    session[:locale] = locale

    # Exécute l'action dans le contexte de cette langue ; with_locale restaure
    # automatiquement la locale précédente une fois le bloc terminé.
    I18n.with_locale(locale, &action)
  end

  # Extrait le code langue préféré depuis l'en-tête HTTP Accept-Language du navigateur.
  # Exemple d'en-tête : "fr-FR,fr;q=0.9,en-US;q=0.8" → on renvoie "fr".
  # Renvoie nil si l'en-tête est absent (laisse alors la résolution retomber sur le défaut).
  def locale_from_browser
    header = request.env["HTTP_ACCEPT_LANGUAGE"]
    return if header.blank?

    # On capture le tout premier code de 2 lettres (la langue la plus prioritaire).
    header.scan(/[a-z]{2}/i).first&.downcase
  end

  # Redirige noctilio-app.fr (sans www) vers www.noctilio-app.fr
  # 301 = redirection permanente — Google transfère le jus SEO vers le domaine canonique
  # Uniquement en production pour ne pas gêner le développement local
  def redirect_to_www
    return unless Rails.env.production? && request.host == "noctilio-app.fr"

    redirect_to "https://www.noctilio-app.fr#{request.fullpath}", status: :moved_permanently
  end

  # Calcule la phase lunaire actuelle en heure de Paris (UTC+1 ou UTC+2 selon DST)
  # Retourne un float entre 0.0 et 1.0 :
  #   0.0 / 1.0 = nouvelle lune
  #   0.25      = premier quartier (croissant → demi-lune droite)
  #   0.5       = pleine lune
  #   0.75      = dernier quartier (demi-lune gauche)
  # Disponible dans tous les controllers qui en ont besoin (dashboard, landing…)
  def current_moon_phase
    # Nouvelle lune de référence connue et précise : 6 janvier 2000 à 18h14 UTC
    # Source : US Naval Observatory
    reference_new_moon = Time.utc(2000, 1, 6, 18, 14, 0)

    # Période synodique (durée d'un cycle complet lune → lune) en secondes
    synodic_period_seconds = 29.530588853 * 24 * 3600

    # Temps actuel en UTC (même référentiel que la nouvelle lune de référence)
    now_utc = Time.now.utc

    # Nombre de secondes écoulées depuis la nouvelle lune de référence
    elapsed = now_utc - reference_new_moon

    # Phase = position dans le cycle, ramenée entre 0.0 et 1.0
    # modulo gère les cycles multiples depuis l'an 2000
    phase = (elapsed % synodic_period_seconds) / synodic_period_seconds

    phase.round(4) # 4 décimales suffisent pour l'affichage
  end
end
