class Child < ApplicationRecord
  # ============================================================
  # Associations
  # ============================================================

  # Un enfant appartient à un utilisateur parent
  belongs_to :user

  # Un enfant peut avoir plusieurs histoires — toutes supprimées si l'enfant est supprimé
  has_many :stories, dependent: :destroy

  # ============================================================
  # Validations
  # ============================================================
  validates :name, presence: true, length: { minimum: 2, maximum: 50 }
  validates :age,  presence: true, numericality: { only_integer: true, greater_than: 0, less_than: 16 }

  # ============================================================
  # Scopes
  # ============================================================

  # Récupère les enfants du plus récent au plus ancien
  scope :ordered, -> { order(created_at: :desc) }

  # ============================================================
  # Méthodes métier
  # ============================================================

  # Génère une description textuelle de l'enfant pour les prompts IA
  # Cette description est injectée dans le prompt de génération d'histoire
  # Exemple : "Léo, un garçon de 6 ans, courageux et curieux, qui adore l'espace"
  def avatar_description
    parts = ["#{name}, #{gender_label} de #{age} ans"]

    # Ajoute les traits de personnalité si définis
    if personality_traits.present?
      parts << "#{personality_traits.join(', ')}"
    end

    # Ajoute les hobbies si définis
    if hobbies.present?
      parts << "qui adore #{hobbies.join(' et ')}"
    end

    # Ajoute la description physique si définie
    if child_description.present?
      parts << child_description
    end

    parts.join(", ")
  end

  private

  # Retourne le genre en français pour la description
  def gender_label
    case gender
    when "boy"   then "garçon"
    when "girl"  then "fille"
    else "enfant"
    end
  end
end
