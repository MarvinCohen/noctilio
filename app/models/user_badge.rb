class UserBadge < ApplicationRecord
  # ============================================================
  # Associations
  # ============================================================

  # Un UserBadge relie un utilisateur à un badge
  belongs_to :user
  belongs_to :badge

  # ============================================================
  # Validations
  # ============================================================

  # Un utilisateur ne peut pas avoir le même badge deux fois
  # (l'index unique en base de données renforce aussi cette règle)
  validates :user_id, uniqueness: { scope: :badge_id, message: "a déjà ce badge" }
  validates :earned_at, presence: true
end
