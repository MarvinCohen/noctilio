# ============================================================
# SeoHelper — outils SEO multilingue (canonical + hreflang)
# ============================================================
# Centralise la construction des URLs absolues utilisées dans le <head> des
# pages publiques :
#   - l'URL canonique de la page courante (dans sa langue)
#   - les balises hreflang (une par langue + x-default) qui disent à Google
#     « cette page existe aussi dans ces autres langues, voici leurs URLs ».
# Tout est construit à partir du chemin de la page, sans préfixe de langue,
# puis re-préfixé pour chaque langue cible.
module SeoHelper
  # Domaine canonique du site (toujours en https + www, voir redirect_to_www)
  SEO_HOST = "https://www.noctilio-app.fr".freeze

  # Renvoie le chemin de la page courante DÉBARRASSÉ de son préfixe de langue.
  # Exemples : "/en/blog" -> "/blog" ; "/es/cgu" -> "/cgu" ; "/blog" -> "/blog".
  # Sert de base commune pour reconstruire l'URL de la page dans n'importe
  # quelle langue.
  def path_without_locale
    # On retire un éventuel préfixe /en /es /de /it /pt en tout début de chemin.
    # (?=/|\z) : le préfixe doit être suivi d'un "/" ou de la fin de chaîne,
    # pour ne pas amputer un mot qui commencerait par ces lettres (ex : /entreprise).
    request.path.sub(%r{\A/(en|es|de|it|pt)(?=/|\z)}, "")
  end

  # Construit l'URL ABSOLUE de la page courante dans la langue demandée.
  def localized_url(locale)
    localized_url_for(path_without_locale, locale)
  end

  # Construit l'URL ABSOLUE d'un chemin DONNÉ (sans préfixe de langue) dans la
  # langue demandée. Utilisé par le sitemap, qui doit générer les URLs de pages
  # autres que la page courante.
  # - FR (langue par défaut) : pas de préfixe -> https://www.noctilio-app.fr/blog
  # - autres langues          : préfixe /xx   -> https://www.noctilio-app.fr/en/blog
  def localized_url_for(base_path, locale)
    # Racine "/" -> chaîne vide, pour éviter une double barre ("//") après le préfixe
    base = (base_path == "/" ? "" : base_path)
    # Préfixe de langue : vide pour le français, "/xx" sinon
    prefix = (locale.to_sym == I18n.default_locale ? "" : "/#{locale}")

    url = "#{SEO_HOST}#{prefix}#{base}"
    # Racine en français : on garde le "/" final pour une URL valide
    url = "#{SEO_HOST}/" if url == SEO_HOST
    url
  end

  # URL canonique de la page courante : la version dans la langue affichée.
  def canonical_url
    localized_url(I18n.locale)
  end

  # Format attendu par Open Graph pour og:locale : "langue_RÉGION" (ex : fr_FR).
  # On associe à chaque langue de l'app une région représentative.
  OG_LOCALES = {
    fr: "fr_FR", en: "en_US", es: "es_ES",
    de: "de_DE", it: "it_IT", pt: "pt_PT"
  }.freeze

  # Renvoie le code og:locale de la langue affichée (repli sur fr_FR).
  def og_locale
    OG_LOCALES.fetch(I18n.locale, "fr_FR")
  end
end
