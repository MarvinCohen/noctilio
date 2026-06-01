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

  # ── Progression ──────────────────────────────────────────────────────────────
  FIRST_STORY        = "first_story"
  FIVE_STORIES       = "five_stories"
  TEN_STORIES        = "ten_stories"
  TWENTY_STORIES     = "twenty_stories"
  THIRTY_STORIES     = "thirty_stories"
  FIFTY_STORIES      = "fifty_stories"
  HUNDRED_STORIES    = "hundred_stories"

  # ── Univers ───────────────────────────────────────────────────────────────────
  SPACE_EXPLORER     = "space_explorer"
  DINO_FAN           = "dino_fan"
  PRINCESS_FAN       = "princess_fan"
  PIRATE_CAPTAIN     = "pirate_captain"
  ANIMAL_LOVER       = "animal_lover"
  WORLD_TRAVELER     = "world_traveler"

  # ── Mode interactif ───────────────────────────────────────────────────────────
  FIRST_INTERACTIVE  = "first_interactive"
  CHOICE_MAKER       = "choice_maker"

  # ── Sagas ─────────────────────────────────────────────────────────────────────
  SAGA_STARTER       = "saga_starter"
  SAGA_MASTER        = "saga_master"

  # ── Styles ────────────────────────────────────────────────────────────────────
  STYLE_EXPLORER     = "style_explorer"
  GHIBLI_FAN         = "ghibli_fan"
  CINEMATIC_PRO      = "cinematic_pro"

  # ── Valeurs éducatives ────────────────────────────────────────────────────────
  KIND_HEART         = "kind_heart"
  COURAGE_HEART      = "courage_heart"
  SHARING_HEART      = "sharing_heart"
  CONFIDENCE_BUILDER = "confidence_builder"

  # ── Thème libre ───────────────────────────────────────────────────────────────
  FREE_SPIRIT        = "free_spirit"
  IMAGINATIVE        = "imaginative"

  # ── Durée ─────────────────────────────────────────────────────────────────────
  QUICK_TALES        = "quick_tales"
  EPIC_READER        = "epic_reader"

  # ── Famille ───────────────────────────────────────────────────────────────────
  TOGETHER           = "together"
  BIG_FAMILY         = "big_family"

  # ── Horaires ──────────────────────────────────────────────────────────────────
  NIGHT_OWL          = "night_owl"
  EARLY_BIRD         = "early_bird"
  MIDNIGHT_TALES     = "midnight_tales"

  # ── Bibliothèque ──────────────────────────────────────────────────────────────
  BOOKWORM           = "bookworm"
  COLLECTOR          = "collector"
  GREAT_LIBRARY      = "great_library"

  # ── Week-end ──────────────────────────────────────────────────────────────────
  WEEKEND_TALES      = "weekend_tales"

  # ============================================================
  # Méthode de classe — vérifie et attribue les badges mérités
  # ============================================================
  # Appelée après chaque création d'histoire complétée.
  # Toutes les données sont préchargées en amont pour éviter les N+1.
  def self.check_and_award(user)
    # Nombre total d'histoires complétées — utilisé par tous les badges de progression
    total_stories = user.stories.completed.count

    # Précharge les IDs de badges déjà obtenus — vérifié en mémoire (O(1)) dans award_if_not_earned
    earned_badge_ids = user.user_badges.pluck(:badge_id)

    # Précharge tous les badges indexés par condition_key — accès O(1) sans SELECT supplémentaire
    all_badges = Badge.all.index_by(&:condition_key)

    # ── Progression ────────────────────────────────────────────────────────────
    award_if_not_earned(user, FIRST_STORY,     earned_badge_ids, all_badges) if total_stories >= 1
    award_if_not_earned(user, FIVE_STORIES,    earned_badge_ids, all_badges) if total_stories >= 5
    award_if_not_earned(user, TEN_STORIES,     earned_badge_ids, all_badges) if total_stories >= 10
    award_if_not_earned(user, TWENTY_STORIES,  earned_badge_ids, all_badges) if total_stories >= 20
    award_if_not_earned(user, THIRTY_STORIES,  earned_badge_ids, all_badges) if total_stories >= 30
    award_if_not_earned(user, FIFTY_STORIES,   earned_badge_ids, all_badges) if total_stories >= 50
    award_if_not_earned(user, HUNDRED_STORIES, earned_badge_ids, all_badges) if total_stories >= 100

    # ── Univers — 3 histoires dans chaque thème ────────────────────────────────
    # Compte par univers en une seule requête groupée pour éviter 5 SELECTs séparés
    world_counts = user.stories.completed.where.not(world_theme: nil)
                       .group(:world_theme).count
    award_if_not_earned(user, SPACE_EXPLORER,  earned_badge_ids, all_badges) if world_counts["space"].to_i >= 3
    award_if_not_earned(user, DINO_FAN,        earned_badge_ids, all_badges) if world_counts["dinos"].to_i >= 3
    award_if_not_earned(user, PRINCESS_FAN,    earned_badge_ids, all_badges) if world_counts["princesses"].to_i >= 3
    award_if_not_earned(user, PIRATE_CAPTAIN,  earned_badge_ids, all_badges) if world_counts["pirates"].to_i >= 3
    award_if_not_earned(user, ANIMAL_LOVER,    earned_badge_ids, all_badges) if world_counts["animals"].to_i >= 3

    # Grand Voyageur — avoir utilisé les 5 univers au moins une fois
    all_worlds = %w[space dinos princesses pirates animals]
    if all_worlds.all? { |w| world_counts[w].to_i >= 1 }
      award_if_not_earned(user, WORLD_TRAVELER, earned_badge_ids, all_badges)
    end

    # ── Mode interactif ────────────────────────────────────────────────────────
    # Premier Choix — avoir une histoire interactive complétée (tous les choix faits)
    if user.stories.completed.where(interactive: true)
           .joins(:story_choices).where.not(story_choices: { chosen_option: nil })
           .exists?
      award_if_not_earned(user, FIRST_INTERACTIVE, earned_badge_ids, all_badges)
    end

    # Maître des Choix — 10 choix interactifs effectués au total
    total_choices = StoryChoice.joins(:story)
                               .where(stories: { id: user.stories.select(:id) })
                               .where.not(chosen_option: nil)
                               .count
    award_if_not_earned(user, CHOICE_MAKER, earned_badge_ids, all_badges) if total_choices >= 10

    # ── Sagas ──────────────────────────────────────────────────────────────────
    # La Suite ! — avoir créé au moins un épisode 2 (histoire avec parent)
    if user.stories.where.not(parent_story_id: nil).exists?
      award_if_not_earned(user, SAGA_STARTER, earned_badge_ids, all_badges)
    end

    # Maître de la Saga — avoir une saga d'au moins 3 épisodes
    # Un épisode 3 a un parent qui lui-même a un parent → double jointure
    has_long_saga = user.stories
                        .joins("INNER JOIN stories AS s2 ON stories.parent_story_id = s2.id")
                        .joins("INNER JOIN stories AS s3 ON s2.parent_story_id = s3.id")
                        .exists?
    award_if_not_earned(user, SAGA_MASTER, earned_badge_ids, all_badges) if has_long_saga

    # ── Styles ─────────────────────────────────────────────────────────────────
    # Compte par style en une seule requête groupée
    style_counts = user.stories.completed.where.not(image_style: nil)
                       .group(:image_style).count
    award_if_not_earned(user, GHIBLI_FAN,    earned_badge_ids, all_badges) if style_counts["ghibli"].to_i >= 5
    award_if_not_earned(user, CINEMATIC_PRO, earned_badge_ids, all_badges) if style_counts["cinematic"].to_i >= 3

    # Artiste Complet — avoir utilisé les 5 styles au moins une fois
    all_styles = %w[ghibli comics pixar watercolor cinematic]
    if all_styles.all? { |s| style_counts[s].to_i >= 1 }
      award_if_not_earned(user, STYLE_EXPLORER, earned_badge_ids, all_badges)
    end

    # ── Valeurs éducatives ─────────────────────────────────────────────────────
    # Compte par valeur en une seule requête groupée
    value_counts = user.stories.where.not(educational_value: nil)
                       .group(:educational_value).count
    award_if_not_earned(user, KIND_HEART,         earned_badge_ids, all_badges) if value_counts["kindness"].to_i >= 3
    award_if_not_earned(user, COURAGE_HEART,      earned_badge_ids, all_badges) if value_counts["courage"].to_i >= 3
    award_if_not_earned(user, SHARING_HEART,      earned_badge_ids, all_badges) if value_counts["sharing"].to_i >= 3
    award_if_not_earned(user, CONFIDENCE_BUILDER, earned_badge_ids, all_badges) if value_counts["confidence"].to_i >= 3

    # ── Thème libre ────────────────────────────────────────────────────────────
    # Histoires avec custom_theme renseigné (pas d'univers prédéfini)
    custom_count = user.stories.completed.where.not(custom_theme: [nil, ""]).count
    award_if_not_earned(user, FREE_SPIRIT,  earned_badge_ids, all_badges) if custom_count >= 1
    award_if_not_earned(user, IMAGINATIVE,  earned_badge_ids, all_badges) if custom_count >= 5

    # ── Durée ──────────────────────────────────────────────────────────────────
    award_if_not_earned(user, QUICK_TALES, earned_badge_ids, all_badges) if user.stories.completed.where(duration_minutes: 5).count >= 5
    award_if_not_earned(user, EPIC_READER, earned_badge_ids, all_badges) if user.stories.completed.where(duration_minutes: 15).exists?

    # ── Famille ────────────────────────────────────────────────────────────────
    # Aventure Partagée — histoire avec au moins 1 enfant supplémentaire
    # extra_child_ids est un tableau PostgreSQL — on vérifie qu'il n'est pas vide
    if user.stories.completed.where("extra_child_ids != '{}'").exists?
      award_if_not_earned(user, TOGETHER, earned_badge_ids, all_badges)
    end

    # Grande Famille — histoire avec 3 héros ou plus (1 principal + 2 extra minimum)
    # array_length(extra_child_ids, 1) retourne la longueur du tableau PostgreSQL
    if user.stories.completed.where("array_length(extra_child_ids, 1) >= 2").exists?
      award_if_not_earned(user, BIG_FAMILY, earned_badge_ids, all_badges)
    end

    # ── Horaires ───────────────────────────────────────────────────────────────
    # Hibou Nocturne — histoire créée entre 21h et 6h
    if user.stories.completed
           .where("EXTRACT(HOUR FROM stories.created_at) >= 21 OR EXTRACT(HOUR FROM stories.created_at) < 6")
           .exists?
      award_if_not_earned(user, NIGHT_OWL, earned_badge_ids, all_badges)
    end

    # Lève-tôt — histoire créée avant 8h du matin
    if user.stories.completed
           .where("EXTRACT(HOUR FROM stories.created_at) < 8")
           .exists?
      award_if_not_earned(user, EARLY_BIRD, earned_badge_ids, all_badges)
    end

    # Conte de Minuit — histoire créée entre minuit et 2h
    if user.stories.completed
           .where("EXTRACT(HOUR FROM stories.created_at) < 2")
           .exists?
      award_if_not_earned(user, MIDNIGHT_TALES, earned_badge_ids, all_badges)
    end

    # ── Bibliothèque ───────────────────────────────────────────────────────────
    saved_count = user.stories.completed.where(saved: true).count
    award_if_not_earned(user, COLLECTOR,     earned_badge_ids, all_badges) if saved_count >= 5
    award_if_not_earned(user, BOOKWORM,      earned_badge_ids, all_badges) if saved_count >= 10
    award_if_not_earned(user, GREAT_LIBRARY, earned_badge_ids, all_badges) if saved_count >= 25

    # ── Week-end ───────────────────────────────────────────────────────────────
    # DOW 0 = dimanche, 6 = samedi en PostgreSQL EXTRACT
    weekend_count = user.stories.completed
                        .where("EXTRACT(DOW FROM stories.created_at) IN (0, 6)")
                        .count
    award_if_not_earned(user, WEEKEND_TALES, earned_badge_ids, all_badges) if weekend_count >= 3
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
