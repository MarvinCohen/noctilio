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

  # Clause descriptive du héros pour le prompt image — en anglais pour gpt-image-1/FLUX
  # Forme : "a young 10-year-old boy with warm brown skin, platinum white-blonde hair
  #          and light blue eyes, named Gégé, wearing a red cape"
  # Objectif : que l'enfant SE RECONNAISSE sur l'illustration. On insiste donc sur
  # l'âge (proportions enfantines) et on traduit chaque couleur en anglais sans
  # ambiguïté (ex: "blanc" → "platinum white-blonde", pas "white" qui fait vieux).
  def image_description
    # Toujours commencer par l'âge : ancre les proportions enfantines du modèle
    clause = "a young #{age}-year-old #{gender_label_en}"

    # Peau : juste après l'âge, en anglais précis
    clause += " with #{skin_tone_en} skin" if skin_tone.present?

    # Cheveux + yeux regroupés dans une formulation naturelle
    features = []
    features << "#{hair_color_en} hair" if hair_color.present?
    features << "#{eye_color_en} eyes"  if eye_color.present?
    # "with X skin, Y hair and Z eyes" si peau présente, sinon "with Y hair and Z eyes"
    if features.any?
      connector = skin_tone.present? ? ", " : " with "
      clause += "#{connector}#{features.join(' and ')}"
    end

    # Prénom — aide à individualiser le personnage
    clause += ", named #{name}"

    # Accessoires / vêtements caractéristiques (description libre du parent)
    clause += ", #{child_description}" if child_description.present?

    clause
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

  # ── Traductions des couleurs FR → EN (sans ambiguïté pour le modèle d'image) ──

  # Cheveux : "blanc/gris" → "platinum white-blonde" pour éviter l'effet "personne âgée".
  # Un enfant aux cheveux clairs doit rester un enfant (blond platine, pas vieillard).
  def hair_color_en
    case hair_color.to_s.downcase
    when /blanc|gris|argent/                 then "platinum white-blonde"
    when /blond/                              then "blonde"
    when /ch[aâ]tain\s*clair/                 then "light brown"
    when /ch[aâ]tain|marron|brun/             then "brown"
    when /noir/                               then "jet black"
    when /roux|rousse|red|ginger/             then "ginger red"
    else hair_color
    end
  end

  # Yeux : traduit les libellés français courants en anglais.
  # "clair" géré avant la couleur de base (ex: "bleu clair" → "light blue").
  def eye_color_en
    case eye_color.to_s.downcase
    when /bleu\s*clair/                       then "light blue"
    when /bleu/                               then "blue"
    when /vert/                               then "green"
    when /noisette/                           then "hazel"
    when /marron|brun/                        then "warm brown"
    when /noir/                               then "dark brown"
    when /gris/                               then "grey"
    else eye_color
    end
  end

  # Peau : traduction nuancée (l'ordre compte — "foncé" avant "brun" simple).
  def skin_tone_en
    case skin_tone.to_s.downcase
    when /éb[eè]ne|noir|très.?foncé/          then "dark ebony"
    when /brun.?foncé|foncé/                  then "dark brown"
    when /brun|caramel|métis|mixed|doré/      then "warm brown"
    when /olive|mat|mediterran/               then "olive"
    when /clair|blanc|fair|p[aâ]le/           then "fair light"
    when /rose/                               then "rosy fair"
    else skin_tone
    end
  end
end
