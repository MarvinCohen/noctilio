# app/controllers/sitemaps_controller.rb
# Sitemap XML dynamique et MULTILINGUE.
# Remplace l'ancien public/sitemap.xml statique : il est désormais généré à
# partir des pages publiques réelles (et de la liste d'articles du blog), avec
# pour chaque page les balises hreflang vers toutes ses versions linguistiques.
# Un seul sitemap couvre toutes les langues (recommandation Google).
class SitemapsController < ApplicationController
  # Le sitemap est public — accessible aux robots sans authentification
  skip_before_action :authenticate_user!

  # GET /sitemap.xml — rend la vue app/views/sitemaps/show.xml.erb
  def show
    # Pages publiques STATIQUES : chemin (sans préfixe de langue) + métadonnées SEO.
    # lastmod = date de dernière modification ; changefreq/priority = indices pour Google.
    @static_pages = [
      { path: "/",                 lastmod: "2026-06-02", changefreq: "weekly",  priority: "1.0" },
      { path: "/a-propos",         lastmod: "2026-06-05", changefreq: "monthly", priority: "0.5" },
      { path: "/cgu",              lastmod: "2026-06-02", changefreq: "monthly", priority: "0.3" },
      { path: "/confidentialite",  lastmod: "2026-06-02", changefreq: "monthly", priority: "0.3" },
      { path: "/mentions-legales", lastmod: "2026-06-02", changefreq: "monthly", priority: "0.3" },
      { path: "/blog",             lastmod: "2026-06-02", changefreq: "weekly",  priority: "0.7" }
    ]

    # Articles du blog : on réutilise la liste maîtresse définie dans BlogController
    # pour rester synchronisé automatiquement quand un article est ajouté.
    @articles = BlogController::ARTICLES

    # Toutes les langues du site (fr + en/es/de/it/pt) — sert à générer les hreflang.
    @locales = I18n.available_locales

    # Rendu XML explicite (la vue est show.xml.erb), sans layout HTML.
    render layout: false, content_type: "application/xml"
  end
end
