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
    # Les valeurs en base sont des clés stables (ex: "black") → on les traduit en libellé FR
    # via I18n (forcé en :fr car ce prompt narratif est toujours rédigé en français)
    parts << "cheveux #{hair_color_fr}"   if hair_color.present?
    parts << "yeux #{eye_color_fr}"       if eye_color.present?
    parts << "peau #{skin_tone_fr}"       if skin_tone.present?

    # Ajoute les traits de personnalité si définis — clés stables traduites en libellé FR
    parts << personality_traits.map { |t| trait_fr(t) }.join(", ") if personality_traits.present?

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

  # ── Traduction des clés stables → libellé FR (pour le prompt narratif) ──
  # Les colonnes hair_color/eye_color/skin_tone stockent désormais des clés stables
  # (ex: "black", "light_blue"). On force I18n en :fr car avatar_description est
  # toujours rédigé en français, quelle que soit la langue d'interface courante.
  # default: la clé brute si jamais une valeur inconnue traînait en base.

  # Cheveux → libellé FR minuscule (ex: "black" → "noir")
  def hair_color_fr
    I18n.t("children.appearance.hair.#{hair_color}", locale: :fr, default: hair_color).downcase
  end

  # Yeux → libellé FR minuscule (ex: "light_blue" → "bleu clair")
  def eye_color_fr
    I18n.t("children.appearance.eyes.#{eye_color}", locale: :fr, default: eye_color).downcase
  end

  # Peau → libellé FR minuscule (ex: "very_light" → "très clair")
  def skin_tone_fr
    I18n.t("children.appearance.skin.#{skin_tone}", locale: :fr, default: skin_tone).downcase
  end

  # Trait de personnalité → libellé FR minuscule (ex: "brave" → "courageux")
  def trait_fr(trait)
    I18n.t("children.appearance.traits.#{trait}", locale: :fr, default: trait).downcase
  end

  # ── Traduction des clés stables → anglais (sans ambiguïté pour le modèle d'image) ──
  # Mapping EXACT clé → anglais (plus de regex floue : les valeurs en base sont des clés).
  # On conserve les nuances pensées pour gpt-image-1 : un enfant aux cheveux clairs doit
  # rester un enfant (blond platine, pas vieillard), peau "warm brown" plutôt que littéral, etc.

  # Cheveux : "white" → "platinum white-blonde" pour éviter l'effet "personne âgée".
  def hair_color_en
    {
      "black"        => "jet black",
      "dark_brown"   => "dark brown",
      "brown"        => "brown",
      "dark_blonde"  => "dark blonde",
      "blonde"       => "blonde",
      "light_blonde" => "light blonde",
      "red"          => "ginger red",
      "white"        => "platinum white-blonde"
    }.fetch(hair_color.to_s, hair_color)
  end

  # Yeux : mapping exact clé → anglais.
  def eye_color_en
    {
      "dark_brown"  => "dark brown",
      "brown"       => "warm brown",
      "hazel"       => "hazel",
      "dark_green"  => "dark green",
      "green"       => "green",
      "light_green" => "light green",
      "dark_blue"   => "dark blue",
      "blue"        => "blue",
      "light_blue"  => "light blue",
      "grey"        => "grey"
    }.fetch(eye_color.to_s, eye_color)
  end

  # Peau : traduction nuancée (warm brown pour les tons chauds, fair light pour les clairs).
  def skin_tone_en
    {
      "ebony"      => "dark ebony",
      "dark_brown" => "dark brown",
      "brown"      => "warm brown",
      "caramel"    => "warm brown",
      "golden"     => "warm golden",
      "olive"      => "olive",
      "beige"      => "fair light",
      "light"      => "fair light",
      "very_light" => "rosy fair"
    }.fetch(skin_tone.to_s, skin_tone)
  end
end
