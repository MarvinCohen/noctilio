class Badge < ApplicationRecord
  # ============================================================
  # Associations
  # ============================================================
  has_many :user_badges
  has_many :users, through: :user_badges

  # ============================================================
  # Validations
  # ============================================================
  validates :name,          presence: true
  validates :condition_key, presence: true, uniqueness: true

  # ============================================================
  # Constantes — clés de conditions d'obtention des badges
  # ============================================================
  # Ces clés sont utilisées dans check_and_award pour savoir
  # quelle condition vérifier
  FIRST_STORY   = "first_story"    # Créer sa première histoire
  FIVE_STORIES  = "five_stories"   # Créer 5 histoires
  TEN_STORIES   = "ten_stories"    # Créer 10 histoires
  NIGHT_OWL     = "night_owl"      # Créer une histoire après 21h
  BOOKWORM      = "bookworm"       # Lire 10 histoires complètes
  KIND_HEART    = "kind_heart"     # Choisir la valeur "kindness" 3 fois

  # ============================================================
  # Méthode de classe — vérifie et attribue les badges mérités
  # ============================================================
  # Appelée après chaque création d'histoire
  # Vérifie toutes les conditions et attribue les badges non encore obtenus
  def self.check_and_award(user)
    total_stories = user.stories.completed.count

    # Badge : Première histoire
    award_if_not_earned(user, FIRST_STORY) if total_stories >= 1

    # Badge : 5 histoires
    award_if_not_earned(user, FIVE_STORIES) if total_stories >= 5

    # Badge : 10 histoires
    award_if_not_earned(user, TEN_STORIES) if total_stories >= 10

    # Badge : Hibou nocturne — histoire créée entre 21h et 6h
    if user.stories.completed.any? { |s| s.created_at.hour >= 21 || s.created_at.hour < 6 }
      award_if_not_earned(user, NIGHT_OWL)
    end

    # Badge : Cœur généreux — valeur "kindness" choisie 3 fois
    if user.stories.where(educational_value: "kindness").count >= 3
      award_if_not_earned(user, KIND_HEART)
    end
  end

  private

  # Attribue un badge à l'utilisateur s'il ne l'a pas encore
  # Trouve le badge par condition_key, puis crée l'association
  def self.award_if_not_earned(user, condition_key)
    badge = find_by(condition_key: condition_key)
    return unless badge
    return if user.badges.include?(badge)

    user.user_badges.create!(badge: badge, earned_at: Time.current)
  end
end
