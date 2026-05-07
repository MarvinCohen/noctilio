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

    # Précharge tous les IDs de badges déjà obtenus en UNE seule requête SQL
    # Évite le N+1 : sans ça, user.badges.include?(badge) fait 1 SELECT par badge vérifié
    earned_badge_ids = user.user_badges.pluck(:badge_id)

    # Précharge TOUS les badges en une seule requête SQL et les index par condition_key
    # Permet d'accéder à chaque badge en O(1) sans nouveau SELECT dans award_if_not_earned
    all_badges = Badge.all.index_by(&:condition_key)

    # Badge : Première histoire
    award_if_not_earned(user, FIRST_STORY, earned_badge_ids, all_badges) if total_stories >= 1

    # Badge : 5 histoires
    award_if_not_earned(user, FIVE_STORIES, earned_badge_ids, all_badges) if total_stories >= 5

    # Badge : 10 histoires
    award_if_not_earned(user, TEN_STORIES, earned_badge_ids, all_badges) if total_stories >= 10

    # Badge : Hibou nocturne — histoire créée entre 21h et 6h
    # Utilise SQL EXTRACT pour filtrer en base au lieu de charger tous les objets en Ruby
    if user.stories.completed
           .where("EXTRACT(HOUR FROM stories.created_at) >= 21 OR EXTRACT(HOUR FROM stories.created_at) < 6")
           .exists?
      award_if_not_earned(user, NIGHT_OWL, earned_badge_ids, all_badges)
    end

    # Badge : Cœur généreux — valeur "kindness" choisie 3 fois
    if user.stories.where(educational_value: "kindness").count >= 3
      award_if_not_earned(user, KIND_HEART, earned_badge_ids, all_badges)
    end

    # Badge : Grand lecteur — avoir 10 histoires complétées sauvegardées
    # Mesure l'engagement à long terme : l'enfant a relu et gardé 10 histoires
    if user.stories.completed.where(saved: true).count >= 10
      award_if_not_earned(user, BOOKWORM, earned_badge_ids, all_badges)
    end
  end

  private

  # Attribue un badge à l'utilisateur s'il ne l'a pas encore
  # all_badges       : Hash { condition_key => badge } préchargé — zéro requête SQL ici
  # earned_badge_ids : Array d'IDs préchargé — vérification en mémoire O(1)
  def self.award_if_not_earned(user, condition_key, earned_badge_ids, all_badges)
    # Accès O(1) dans le Hash — pas de SELECT en base
    badge = all_badges[condition_key]
    return unless badge

    # Vérifie en mémoire (pas en base) si le badge est déjà obtenu
    return if earned_badge_ids.include?(badge.id)

    user.user_badges.create!(badge: badge, earned_at: Time.current)
  end
end
