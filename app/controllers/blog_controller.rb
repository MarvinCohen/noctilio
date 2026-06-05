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
  # Note SEO : les dates sont étalées sur 8 semaines pour simuler un rythme de publication
  # naturel — Google pénalise les lots d'articles publiés le même jour (signal de contenu en masse)
  ARTICLES = [
    {
      slug: "histoires-du-soir-enfant",
      title: "5 idées d'histoires du soir pour endormir ton enfant facilement",
      description: "Découvrez 5 types d'histoires du soir qui aident les enfants à s'endormir sereinement. Conseils pratiques et exemples personnalisés par l'IA.",
      published_at: Date.new(2026, 4, 7), # Article phare — publié le plus tôt
      reading_time: 5,
      # FAQs — questions fréquentes des parents, citables par les AI Overviews et LLM
      faqs: [
        {
          question: "Quelle est la meilleure histoire pour endormir un enfant de 3 ans ?",
          answer: "Les histoires courtes (3 à 5 minutes) avec un héros rassurant qui rentre chez lui et s'endort sont les plus efficaces pour les 3 ans. Les thèmes liés à la nuit, aux étoiles et aux animaux familiers apaisent naturellement l'enfant pendant la transition veille-sommeil."
        },
        {
          question: "Comment rendre une histoire du soir plus efficace ?",
          answer: "L'efficacité d'une histoire du soir repose sur trois éléments : un rythme lent et une voix douce, un héros auquel l'enfant s'identifie (idéalement avec son prénom), et une fin apaisante où le personnage s'endort. Répéter le même rituel chaque soir renforce l'effet de signal de sommeil."
        },
        {
          question: "À partir de quel âge peut-on raconter des histoires du soir ?",
          answer: "Les histoires du soir peuvent commencer dès 18 mois avec des histoires très simples (2-3 minutes, un personnage, un seul événement). À partir de 3 ans, l'enfant suit une narrative complète avec début, péripétie et fin. Le mode interactif (choix dans l'histoire) est adapté à partir de 4-5 ans."
        }
      ]
    },
    {
      slug: "conte-personnalise-ia-enfant",
      title: "Comment l'IA génère des contes personnalisés pour votre enfant",
      description: "Comprendre comment GPT-4o crée des histoires uniques adaptées à l'âge, aux goûts et à la personnalité de chaque enfant. Guide pour les parents.",
      published_at: Date.new(2026, 4, 14),
      reading_time: 6,
      # FAQs — questions parents sur l'IA et les histoires générées
      faqs: [
        {
          question: "Est-ce que les histoires générées par l'IA sont adaptées à l'âge de l'enfant ?",
          answer: "Oui. Noctilio adapte automatiquement le vocabulaire, la complexité narrative et la longueur selon l'âge indiqué dans le profil de l'enfant. Un enfant de 3 ans recevra une histoire courte avec des mots simples, tandis qu'un enfant de 8 ans aura une histoire plus longue avec des rebondissements."
        },
        {
          question: "L'IA peut-elle intégrer le prénom de mon enfant dans l'histoire ?",
          answer: "Absolument. C'est même la fonctionnalité centrale de Noctilio : le héros de chaque histoire porte le prénom de votre enfant. L'IA intègre aussi ses personnages préférés, son univers favori (espace, dinosaures, princesses, pirates, animaux) et ses traits de personnalité pour créer une histoire unique."
        },
        {
          question: "Les histoires générées par l'IA sont-elles sûres pour les enfants ?",
          answer: "Oui. GPT-4o est configuré avec des instructions strictes pour générer uniquement du contenu positif, bienveillant et adapté aux enfants de 2 à 10 ans. Les histoires évitent toute violence, peur excessive, ou contenu inapproprié. Chaque génération respecte les valeurs éducatives sélectionnées par le parent."
        }
      ]
    },
    {
      slug: "histoires-enfant-4-ans",
      title: "Histoires pour enfant de 4 ans : ce qui les captive vraiment",
      description: "Quels types d'histoires conviennent le mieux aux enfants de 4 ans ? Longueur, personnages, structure narrative — tout ce qu'il faut savoir.",
      published_at: Date.new(2026, 4, 21),
      reading_time: 5
    },
    {
      slug: "histoires-enfant-3-ans",
      title: "Histoires pour enfant de 3 ans : le rituel du soir qui apaise",
      description: "À 3 ans, l'histoire du soir est un rituel de transition essentiel. Découvrez la longueur idéale, les univers rassurants et comment gérer la peur du noir.",
      published_at: Date.new(2026, 4, 28),
      reading_time: 5
    },
    {
      slug: "histoires-enfant-5-ans",
      title: "Histoires pour enfant de 5 ans : les univers qui captivent vraiment",
      description: "À 5 ans, l'imagination explose. Quels types d'histoires fonctionnent le mieux ? Structure narrative, émotions complexes, mode interactif — guide complet.",
      published_at: Date.new(2026, 5, 5),
      reading_time: 5
    },
    {
      slug: "histoire-personnalisee-prenom-enfant",
      title: "Histoire personnalisée avec le prénom de votre enfant : pourquoi ça change tout",
      description: "Entendre son prénom dans une histoire active l'attention et la mémoire de l'enfant. Comprendre la puissance de la personnalisation et comment l'IA va plus loin.",
      published_at: Date.new(2026, 5, 12),
      reading_time: 5
    },
    {
      slug: "conte-interactif-enfant",
      title: "Conte interactif enfant : quand votre enfant choisit la suite de l'histoire",
      description: "Le conte interactif transforme l'écoute en participation. À partir de 4 ans, votre enfant devient co-auteur de son histoire du soir. Bénéfices et fonctionnement.",
      published_at: Date.new(2026, 5, 19),
      reading_time: 5
    },
    {
      slug: "histoire-courte-enfant-soir",
      title: "Histoire courte pour enfant : 5 minutes pour un rituel du soir réussi",
      description: "Une histoire courte bien construite est souvent plus efficace qu'une longue pour l'endormissement. Structure, thèmes et conseils pour les soirs express.",
      published_at: Date.new(2026, 5, 26),
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
