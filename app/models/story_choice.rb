class StoryChoice < ApplicationRecord
  # ============================================================
  # Associations
  # ============================================================

  # Un choix appartient à une histoire
  belongs_to :story

  # ============================================================
  # Validations
  # ============================================================
  validates :question, presence: true
  validates :option_a, presence: true
  validates :option_b, presence: true
  validates :step_number, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # chosen_option doit être 'a', 'b', ou nil (pas encore choisi)
  validates :chosen_option, inclusion: { in: %w[a b] }, allow_nil: true

  # ============================================================
  # Scopes
  # ============================================================

  # Choix non encore effectués (l'enfant n'a pas encore décidé)
  scope :pending,  -> { where(chosen_option: nil) }

  # Choix déjà effectués
  scope :resolved, -> { where.not(chosen_option: nil) }

  # Trier dans l'ordre des étapes
  scope :ordered,  -> { order(:step_number) }

  # ============================================================
  # Méthodes métier
  # ============================================================

  # Retourne true si l'enfant a déjà fait ce choix
  def resolved?
    chosen_option.present?
  end

  # Retourne le texte de l'option choisie
  def chosen_text
    return nil unless resolved?

    chosen_option == "a" ? option_a : option_b
  end
end
