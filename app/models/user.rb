class User < ApplicationRecord
  # ============================================================
  # Devise — gère l'authentification (connexion, mot de passe...)
  # ============================================================
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         # omniauthable permet à Devise de gérer les connexions via fournisseurs externes
         # providers: liste des fournisseurs autorisés (on peut en ajouter d'autres plus tard)
         :omniauthable, omniauth_providers: [:google_oauth2]

  # ============================================================
  # Pay — gère l'abonnement Stripe
  # pay_customer crée automatiquement un client Stripe
  # et ajoute les méthodes : subscribed?, payment_methods, charges...
  # ============================================================
  pay_customer

  # ============================================================
  # Associations
  # ============================================================

  # Un utilisateur possède plusieurs enfants
  has_many :children, dependent: :destroy

  # Un utilisateur accède à toutes ses histoires via ses enfants
  has_many :stories, through: :children

  # Badges gagnés par l'utilisateur
  has_many :user_badges, dependent: :destroy
  has_many :badges, through: :user_badges

  # ============================================================
  # Callbacks
  # ============================================================

  # Envoie l'email de bienvenue après la création du compte
  # after_commit garantit que l'envoi se fait une fois l'utilisateur bien sauvegardé en base
  after_commit :send_welcome_email, on: :create

  # ============================================================
  # Validations
  # ============================================================
  validates :first_name, presence: true, length: { maximum: 50 }
  validates :last_name,  presence: true, length: { maximum: 50 }

  # ============================================================
  # Méthodes métier
  # ============================================================

  # Retourne true si l'utilisateur a un abonnement premium actif
  # subscribed? est fourni par le gem Pay — vérifie en base si l'abonnement Stripe est actif
  def premium?
    # Les admins sont toujours premium — accès illimité pour tester l'app
    return true if admin?

    # Vérifie si l'utilisateur a un abonnement Pay actif (Stripe)
    # Pay met à jour ce statut automatiquement via les webhooks Stripe
    payment_processor.present? && payment_processor.subscribed?
  end

  # Retourne true si l'utilisateur est administrateur de l'application
  # Pour passer un compte admin : User.find_by(email: "...").update!(admin: true)
  # OU via Rails console Heroku : heroku run rails console
  def admin?
    admin == true
  end

  # Compte les histoires créées cette semaine (tous enfants confondus)
  # beginning_of_week = lundi 00:00 → le quota gratuit se réinitialise chaque lundi
  def stories_this_week
    stories.where(created_at: Time.current.beginning_of_week..)
           .count
  end

  # Retourne true si l'utilisateur peut encore créer une histoire
  # — Premium : illimité
  # — Gratuit : limité à 3 histoires par semaine
  def can_create_story?
    return true if premium?

    stories_this_week < 3
  end

  # ============================================================
  # Offre découverte — la 1re histoire du compte est en accès complet
  # ============================================================
  # But : montrer toute la valeur (illustration + audio + mode interactif)
  # dès la 1re histoire pour donner envie de s'abonner. Dès la 2e histoire,
  # un compte gratuit repasse en "texte seul".

  # Retourne true si `story` est la TOUTE PREMIÈRE histoire du compte.
  # On compare son id à la plus petite clé primaire des histoires de l'utilisateur :
  # la plus petite id = la 1re histoire créée. Pas besoin de colonne dédiée.
  # NB : si l'utilisateur supprime sa 1re histoire, la suivante redevient "la 1re"
  # (offre re-débloquée) — limite assumée au lancement, risque faible.
  def welcome_story?(story)
    # story.id peut être nil si l'histoire n'est pas encore sauvegardée → false
    # On compare à l'id de la 1re histoire, mémoïsé pour ne pas relancer la requête
    # `stories.minimum(:id)` à chaque appel (full_experience_for? l'appelle souvent).
    story.id.present? && story.id == first_story_id
  end

  # Id de la TOUTE PREMIÈRE histoire du compte (plus petite clé primaire), ou nil
  # si le compte n'a encore aucune histoire. Mémoïsé via `defined?` plutôt que `||=`
  # car la valeur peut légitimement être nil : avec `||=` un compte sans histoire
  # relancerait la requête à chaque appel. `defined?` met en cache même un nil.
  def first_story_id
    return @first_story_id if defined?(@first_story_id)

    @first_story_id = stories.minimum(:id)
  end

  # Décide si une histoire donnée a droit à l'expérience complète
  # (illustration + audio + mode interactif) : Premium toujours, sinon
  # uniquement la 1re histoire offerte. Utilisée par le job et l'endpoint audio.
  def full_experience_for?(story)
    premium? || welcome_story?(story)
  end

  # Retourne true tant que l'utilisateur n'a encore créé AUCUNE histoire :
  # sa prochaine histoire sera donc sa 1re et bénéficiera de l'offre découverte.
  # Utilisée par le formulaire de création pour activer le toggle "mode interactif"
  # et afficher la bannière d'offre AVANT que l'histoire n'existe en base.
  def first_story_pending?
    stories.none?
  end

  # Retourne le nom complet de l'utilisateur
  def full_name
    "#{first_name} #{last_name}"
  end

  # Calcule les points d'expérience (XP) de l'utilisateur
  # Règle : 100 XP par histoire terminée + 50 XP par badge obtenu
  # Mémoïsation (@xp_points ||=) : le résultat fait 2 requêtes SQL (count des
  # histoires terminées + count des badges). Comme level, xp_in_current_level,
  # xp_to_next_level et level_progress rappellent tous xp_points, on ne le calcule
  # qu'UNE fois par instance puis on réutilise la valeur en cache.
  def xp_points
    @xp_points ||= (stories.completed.count * 100) + (user_badges.count * 50)
  end

  # Niveau de l'utilisateur, dérivé de l'XP.
  # Règle : 1 niveau tous les 500 XP, en commençant au niveau 1.
  # Centralisé ici (Fat Model) pour être réutilisé par la sidebar ET la salle
  # des trophées, qui calculaient le niveau chacune de leur côté avant.
  def level
    (xp_points / XP_PER_LEVEL) + 1
  end

  # ============================================================
  # Progression — données pour la carte "rituel du soir" du dashboard
  # ============================================================
  # Palier d'XP par niveau — constante centrale pour rester cohérent avec level.
  # On l'utilise aussi dans level ci-dessus pour ne jamais dupliquer le 500.
  XP_PER_LEVEL = 500

  # XP accumulés DANS le niveau courant (de 0 à 499).
  # Exemple : 1 200 XP total → niveau 3 → 200 XP dans le niveau courant.
  def xp_in_current_level
    xp_points % XP_PER_LEVEL
  end

  # XP qu'il reste à gagner avant d'atteindre le niveau suivant.
  # Sert à afficher "encore 300 XP avant le niveau 4" sur le dashboard.
  def xp_to_next_level
    XP_PER_LEVEL - xp_in_current_level
  end

  # Avancement vers le niveau suivant, en pourcentage (0 à 100).
  # Pilote la largeur de la barre de progression XP du dashboard.
  def level_progress
    (xp_in_current_level * 100 / XP_PER_LEVEL)
  end

  # ============================================================
  # Constellation du soir — habitude douce, jamais punitive
  # ============================================================
  # Renvoie un tableau de `days` booléens, du plus ancien au plus récent :
  # true si AU MOINS une histoire TERMINÉE a été créée ce jour-là.
  # But : afficher une constellation (étoiles allumées) qui valorise les soirs
  # de lecture SANS culpabiliser les soirs manqués (pas de "streak" cassé).
  def recent_story_nights(days = 7)
    # Date du plus ancien jour de la fenêtre (ex : il y a 6 jours pour 7 jours)
    start_date = (days - 1).days.ago.to_date

    # On récupère en une seule requête les dates de création des histoires
    # TERMINÉES de la fenêtre, converties en jour (sans l'heure), dédoublonnées.
    # On filtre sur .completed : une génération échouée ou en attente ne doit
    # pas allumer une étoile (sinon la constellation mentirait sur le rituel).
    lit_dates = stories.completed.where(created_at: start_date.beginning_of_day..)
                       .pluck(:created_at)
                       .map(&:to_date)
                       .to_set

    # Pour chaque jour de la fenêtre (du plus ancien au plus récent),
    # true si une histoire existe ce jour-là.
    (0...days).map { |offset| lit_dates.include?((days - 1 - offset).days.ago.to_date) }
  end

  # ============================================================
  # Méthode de classe — connexion / création via Google OAuth
  # ============================================================
  # Appelée par OmniauthCallbacksController après le retour de Google.
  # auth est le hash OmniAuth renvoyé par Google, qui contient :
  #   auth.provider   → "google_oauth2"
  #   auth.uid        → identifiant unique Google de l'utilisateur
  #   auth.info.email → email Google
  #   auth.info.first_name / auth.info.last_name → prénom/nom
  def self.from_omniauth(auth)
    # 1. On cherche d'abord un compte DÉJÀ lié à ce compte Google (provider + uid)
    #    Cas le plus courant : l'utilisateur s'est déjà connecté via Google avant.
    user = find_by(provider: auth.provider, uid: auth.uid)
    return user if user

    # 2. Sinon, on cherche un compte existant avec le MÊME email.
    #    Cas : l'utilisateur s'était inscrit avec email/mot de passe, puis tente
    #    de se connecter via Google. Sans ça, on tomberait sur "email déjà utilisé".
    #    On lie alors son compte à Google (provider + uid) pour les prochaines fois.
    user = find_by(email: auth.info.email)
    if user
      user.update(provider: auth.provider, uid: auth.uid)
      return user
    end

    # 3. Aucun compte existant → on en crée un nouveau à partir des infos Google.
    #    Le bloc `do |new_user|` est exécuté avant la sauvegarde.
    create do |new_user|
      new_user.provider   = auth.provider
      new_user.uid        = auth.uid
      new_user.email      = auth.info.email
      new_user.first_name = auth.info.first_name.presence || auth.info.email.split("@").first
      new_user.last_name  = auth.info.last_name.presence  || "-"
      # On génère un mot de passe aléatoire fort — l'utilisateur Google n'en aura jamais besoin
      new_user.password   = Devise.friendly_token[0, 20]
    end
  end

  private

  # Envoie l'email de bienvenue en arrière-plan via Solid Queue
  # deliver_later évite de bloquer l'inscription si le SMTP est lent
  def send_welcome_email
    WelcomeMailer.welcome_email(self).deliver_later
  end
end
