# app/controllers/blog_controller.rb
# Contrôleur du blog SEO — articles publics sur les histoires pour enfants.
# Les articles sont des vues ERB statiques (pas de base de données).
# Chaque article est défini dans ARTICLES et rendu via app/views/blog/show.html.erb.
class BlogController < ApplicationController
  # Le blog est public — pas besoin d'être connecté pour lire un article
  skip_before_action :authenticate_user!

  # Liste de tous les articles publiés — à compléter au fur et à mesure
  # Chaque entrée contient :
  #   slug         → URL de l'article (/blog/<slug>)
  #   title        → titre SEO de la page
  #   description  → meta description (150 caractères max)
  #   published_at → date de publication (affichée et utilisée par les moteurs de recherche)
  #   reading_time → temps de lecture estimé en minutes
  ARTICLES = [
    {
      slug: "histoires-du-soir-enfant",
      title: "5 idées d'histoires du soir pour endormir ton enfant facilement",
      description: "Découvrez 5 types d'histoires du soir qui aident les enfants à s'endormir sereinement. Conseils pratiques et exemples personnalisés par l'IA.",
      published_at: Date.new(2026, 6, 2),
      reading_time: 5
    },
    {
      slug: "conte-personnalise-ia-enfant",
      title: "Comment l'IA génère des contes personnalisés pour votre enfant",
      description: "Comprendre comment GPT-4o crée des histoires uniques adaptées à l'âge, aux goûts et à la personnalité de chaque enfant. Guide pour les parents.",
      published_at: Date.new(2026, 6, 2),
      reading_time: 6
    },
    {
      slug: "histoires-enfant-4-ans",
      title: "Histoires pour enfant de 4 ans : ce qui les captive vraiment",
      description: "Quels types d'histoires conviennent le mieux aux enfants de 4 ans ? Longueur, personnages, structure narrative — tout ce qu'il faut savoir.",
      published_at: Date.new(2026, 6, 2),
      reading_time: 5
    },
    {
      slug: "histoires-enfant-3-ans",
      title: "Histoires pour enfant de 3 ans : le rituel du soir qui apaise",
      description: "À 3 ans, l'histoire du soir est un rituel de transition essentiel. Découvrez la longueur idéale, les univers rassurants et comment gérer la peur du noir.",
      published_at: Date.new(2026, 6, 2),
      reading_time: 5
    },
    {
      slug: "histoires-enfant-5-ans",
      title: "Histoires pour enfant de 5 ans : les univers qui captivent vraiment",
      description: "À 5 ans, l'imagination explose. Quels types d'histoires fonctionnent le mieux ? Structure narrative, émotions complexes, mode interactif — guide complet.",
      published_at: Date.new(2026, 6, 2),
      reading_time: 5
    },
    {
      slug: "histoire-personnalisee-prenom-enfant",
      title: "Histoire personnalisée avec le prénom de votre enfant : pourquoi ça change tout",
      description: "Entendre son prénom dans une histoire active l'attention et la mémoire de l'enfant. Comprendre la puissance de la personnalisation et comment l'IA va plus loin.",
      published_at: Date.new(2026, 6, 2),
      reading_time: 5
    },
    {
      slug: "conte-interactif-enfant",
      title: "Conte interactif enfant : quand votre enfant choisit la suite de l'histoire",
      description: "Le conte interactif transforme l'écoute en participation. À partir de 4 ans, votre enfant devient co-auteur de son histoire du soir. Bénéfices et fonctionnement.",
      published_at: Date.new(2026, 6, 2),
      reading_time: 5
    },
    {
      slug: "histoire-courte-enfant-soir",
      title: "Histoire courte pour enfant : 5 minutes pour un rituel du soir réussi",
      description: "Une histoire courte bien construite est souvent plus efficace qu'une longue pour l'endormissement. Structure, thèmes et conseils pour les soirs express.",
      published_at: Date.new(2026, 6, 2),
      reading_time: 4
    }
  ].freeze

  # GET /blog — liste tous les articles publiés
  def index
    # @articles est disponible dans la vue blog/index.html.erb
    @articles = ARTICLES
  end

  # GET /blog/:slug — affiche un article précis
  def show
    # Cherche l'article correspondant au slug dans l'URL
    @article = ARTICLES.find { |a| a[:slug] == params[:slug] }

    # Si le slug n'existe pas → page 404 standard Rails
    raise ActionController::RoutingError, "Article introuvable : #{params[:slug]}" if @article.nil?

    # Nom du partial qui contient le contenu de l'article
    # ex: slug "histoires-du-soir-enfant" → views/blog/_histoires-du-soir-enfant.html.erb
    @partial = @article[:slug]
  end
end
