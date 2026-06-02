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
      slug:         "histoires-du-soir-enfant",
      title:        "5 idées d'histoires du soir pour endormir ton enfant facilement",
      description:  "Découvrez 5 types d'histoires du soir qui aident les enfants à s'endormir sereinement. Conseils pratiques et exemples personnalisés par l'IA.",
      published_at: Date.new(2026, 6, 2),
      reading_time: 5
    },
    {
      slug:         "conte-personnalise-ia-enfant",
      title:        "Comment l'IA génère des contes personnalisés pour votre enfant",
      description:  "Comprendre comment GPT-4o crée des histoires uniques adaptées à l'âge, aux goûts et à la personnalité de chaque enfant. Guide pour les parents.",
      published_at: Date.new(2026, 6, 2),
      reading_time: 6
    },
    {
      slug:         "histoires-enfant-4-ans",
      title:        "Histoires pour enfant de 4 ans : ce qui les captive vraiment",
      description:  "Quels types d'histoires conviennent le mieux aux enfants de 4 ans ? Longueur, personnages, structure narrative — tout ce qu'il faut savoir.",
      published_at: Date.new(2026, 6, 2),
      reading_time: 5
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
    if @article.nil?
      raise ActionController::RoutingError, "Article introuvable : #{params[:slug]}"
    end

    # Nom du partial qui contient le contenu de l'article
    # ex: slug "histoires-du-soir-enfant" → views/blog/_histoires-du-soir-enfant.html.erb
    @partial = @article[:slug]
  end
end
