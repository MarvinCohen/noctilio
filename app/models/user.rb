class User < ApplicationRecord
  # ============================================================
  # Devise — gère l'authentification (connexion, mot de passe...)
  # ============================================================
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

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

  # Compte les histoires créées ce mois-ci (tous enfants confondus)
  def stories_this_month
    stories.where(created_at: Time.current.beginning_of_month..)
           .count
  end

  # Retourne true si l'utilisateur peut encore créer une histoire
  # — Premium : illimité
  # — Gratuit : limité à 3 histoires par mois
  def can_create_story?
    return true if premium?

    stories_this_month < 3
  end

  # Retourne le nom complet de l'utilisateur
  def full_name
    "#{first_name} #{last_name}"
  end

  # Calcule les points d'expérience (XP) de l'utilisateur
  # Règle : 100 XP par histoire terminée + 50 XP par badge obtenu
  def xp_points
    (stories.completed.count * 100) + (user_badges.count * 50)
  end

  private

  # Envoie l'email de bienvenue en arrière-plan via Solid Queue
  # deliver_later évite de bloquer l'inscription si le SMTP est lent
  def send_welcome_email
    WelcomeMailer.welcome_email(self).deliver_later
  end
end
