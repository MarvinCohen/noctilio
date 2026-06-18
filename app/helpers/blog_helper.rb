# ============================================================
# BlogHelper — titres et descriptions d'articles localisés
# ============================================================
# Les articles sont définis en FRANÇAIS dans BlogController::ARTICLES (source
# unique). Pour les autres langues, on stocke la traduction dans les fichiers
# blog.<locale>.yml sous la clé blog.articles.<slug>.{title,description}.
# Ces helpers renvoient la version traduite si elle existe, sinon retombent
# (default:) sur le texte français du contrôleur. Ainsi le français n'est pas
# dupliqué dans les fichiers YAML.
module BlogHelper
  # Titre de l'article dans la langue courante (repli : titre FR du contrôleur)
  def blog_article_title(article)
    t("blog.articles.#{article[:slug]}.title", default: article[:title])
  end

  # Description de l'article dans la langue courante (repli : description FR)
  def blog_article_description(article)
    t("blog.articles.#{article[:slug]}.description", default: article[:description])
  end

  # FAQs de l'article dans la langue courante (pour le schema FAQPage).
  # Renvoie un tableau de hashes { question:, answer: }.
  # Les traductions sont stockées dans blog.<locale>.yml sous
  # blog.articles.<slug>.faqs ; en français (ou si la traduction manque),
  # on retombe sur les FAQs définies dans le contrôleur (source de vérité).
  # Articles sans FAQ : renvoie un tableau vide (le schema n'est alors pas injecté).
  def blog_article_faqs(article)
    # default: nil → si la clé n'existe pas dans le YAML de la locale, on obtient nil
    translated = t("blog.articles.#{article[:slug]}.faqs", default: nil)
    # presence : un tableau vide ou nil retombe sur les FAQs FR du contrôleur
    translated.presence || article[:faqs] || []
  end
end
