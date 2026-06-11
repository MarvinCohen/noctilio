class Child < ApplicationRecord
  # ============================================================
  # Associations
  # ============================================================

  # Un enfant appartient à un utilisateur parent
  belongs_to :user

  # Un enfant peut avoir plusieurs histoires — toutes supprimées si l'enfant est supprimé
  has_many :stories, dependent: :destroy

  # ============================================================
  # Consentement parental (RGPD)
  # ============================================================
  # Attribut VIRTUEL : pas de colonne en base — il sert uniquement à valider
  # la case à cocher du formulaire de création. On ne stocke pas la valeur,
  # le fait que le profil existe prouve que la case a été cochée à la création.
  attr_accessor :parental_consent

  # ============================================================
  # Validations
  # ============================================================
  validates :name, presence: true, length: { minimum: 2, maximum: 50 }
  validates :age,  presence: true, numericality: { only_integer: true, greater_than: 0, less_than: 16 }

  # RGPD — données de mineurs : le parent doit cocher la case de consentement.
  # acceptance: true → n'accepte que "1" ou true (la checkbox cochée envoie "1")
  # on: :create → uniquement à la création (pas redemandé à chaque modification)
  # Note : si le champ est nil (création via console/seeds/tests), la validation
  # est ignorée par défaut — elle ne s'applique donc qu'au formulaire web,
  # où la checkbox envoie toujours "0" (décochée) ou "1" (cochée).
  validates :parental_consent, acceptance: { message: "doit être accepté pour créer un profil enfant" }, on: :create

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

    # Ajoute les attributs physiques explicites — indispensables pour la cohérence des illustrations
    parts << "cheveux #{hair_color}"   if hair_color.present?
    parts << "yeux #{eye_color}"       if eye_color.present?
    parts << "peau #{skin_tone}"       if skin_tone.present?

    # Ajoute les traits de personnalité si définis
    parts << personality_traits.join(", ") if personality_traits.present?

    # Ajoute les hobbies si définis
    parts << "qui adore #{hobbies.join(' et ')}" if hobbies.present?

    # Ajoute la description libre (accessoires, vêtements, détails uniques)
    parts << child_description if child_description.present?

    parts.join(", ")
  end

  # Description physique précise pour le prompt image — en anglais pour FLUX/DALL-E
  # Les modèles de diffusion répondent mieux aux descriptions physiques en anglais
  def image_description
    parts = ["#{name}, #{age} year old #{gender_label_en}"]

    # Caractéristiques physiques — placées EN PREMIER car les modèles leur donnent plus de poids
    parts << "blonde hair"                        if hair_color&.match?(/blond/i)
    parts << "#{hair_color} hair"                 if hair_color.present? && !hair_color.match?(/blond/i)
    parts << "green eyes"                         if eye_color&.match?(/vert/i)
    parts << "#{eye_color} eyes"                  if eye_color.present? && !eye_color.match?(/vert/i)
    # Traduit la couleur de peau en anglais précis pour le modèle de diffusion
    if skin_tone.present?
      parts << case skin_tone.downcase
               when /éb[eè]ne|noir|très.?foncé/ then "very dark black ebony skin"
               when /foncé|brun.?foncé/          then "dark brown skin"
               when /métis|mixed|caramel|doré/   then "warm golden brown mixed skin"
               when /olive|mat|mediterran/        then "olive mediterranean skin"
               when /clair|fair|blanc/            then "fair light skin"
               when /rose|pale/                   then "pale rosy skin"
               else "#{skin_tone} skin"
               end
    end

    # Accessoires et vêtements caractéristiques depuis la description libre
    parts << child_description if child_description.present?

    parts.join(", ")
  end

  private

  # Retourne le genre en français pour la description narrative
  def gender_label
    case gender
    when "boy"   then "garçon"
    when "girl"  then "fille"
    else "enfant"
    end
  end

  # Retourne le genre en anglais pour les prompts image
  def gender_label_en
    case gender
    when "boy"   then "boy"
    when "girl"  then "girl"
    else "child"
    end
  end
end
