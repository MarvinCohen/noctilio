# ============================================================
# Migration de DONNÉES : convertit les libellés français stockés
# dans les profils enfants en CLÉS STABLES (i18n).
#
# Pourquoi ?
#   Avant : la couleur de cheveux était stockée en français ("noir", "blond").
#   Cela cassait l'internationalisation : impossible d'afficher le libellé
#   dans une autre langue, et l'IA recevait directement du texte FR.
#   Après : on stocke une clé stable ("black", "blonde") et on traduit
#   le libellé à l'affichage via I18n (children.appearance.*).
#
# Réversibilité :
#   up   = ancien libellé FR  → clé stable
#   down = clé stable         → libellé FR canonique (best-effort)
#   Les traits de personnalité obsolètes (absents du formulaire actuel)
#   sont supprimés au passage : ce sont d'anciennes données de test.
# ============================================================
class ConvertChildrenAppearanceToKeys < ActiveRecord::Migration[8.1]
  # ── Tables de correspondance LIBELLÉ FR (downcasé) → CLÉ STABLE ──
  # On normalise en minuscules dans le code pour absorber les variantes
  # ("Curieux" / "curieux") et les formes féminines.

  HAIR_FR_TO_KEY = {
    "noir" => "black",
    "châtain foncé" => "dark_brown", "chatain foncé" => "dark_brown",
    "châtain" => "brown", "chatain" => "brown",
    "blond foncé" => "dark_blonde",
    "blond" => "blonde",
    "blond clair" => "light_blonde",
    "roux" => "red",
    "blanc" => "white"
  }.freeze

  EYES_FR_TO_KEY = {
    "marron foncé" => "dark_brown",
    "marron" => "brown",
    "noisette" => "hazel",
    "vert foncé" => "dark_green",
    "vert" => "green",
    "vert clair" => "light_green",
    "bleu foncé" => "dark_blue",
    "bleu" => "blue",
    "bleu clair" => "light_blue",
    "gris" => "grey"
  }.freeze

  SKIN_FR_TO_KEY = {
    "ébène" => "ebony", "ebene" => "ebony",
    "brun foncé" => "dark_brown",
    "brun" => "brown",
    "caramel" => "caramel",
    "doré" => "golden", "dorée" => "golden",
    "olive" => "olive",
    "beige" => "beige",
    "clair" => "light",
    "très clair" => "very_light", "tres clair" => "very_light"
  }.freeze

  # Traits : seuls les 8 traits du formulaire actuel sont conservés.
  # Les variantes (majuscule, féminin) sont normalisées ; les traits
  # obsolètes (déterminé, empathique, etc.) seront filtrés (→ nil).
  TRAITS_FR_TO_KEY = {
    "courageux" => "brave", "courageuse" => "brave",
    "curieux" => "curious", "curieuse" => "curious",
    "timide" => "shy",
    "drôle" => "funny", "drole" => "funny",
    "généreux" => "generous", "généreuse" => "generous",
    "créatif" => "creative", "créative" => "creative",
    "aventurier" => "adventurous", "aventurière" => "adventurous",
    "doux" => "gentle", "douce" => "gentle"
  }.freeze

  # ── Tables inverses CLÉ → LIBELLÉ FR canonique (pour le down) ──
  HAIR_KEY_TO_FR  = HAIR_FR_TO_KEY.invert.freeze
  EYES_KEY_TO_FR  = EYES_FR_TO_KEY.invert.freeze
  SKIN_KEY_TO_FR  = SKIN_FR_TO_KEY.invert.freeze
  TRAITS_KEY_TO_FR = { # un libellé canonique par clé
    "brave" => "courageux", "curious" => "curieux", "shy" => "timide",
    "funny" => "drôle", "generous" => "généreux", "creative" => "créatif",
    "adventurous" => "aventurier", "gentle" => "doux"
  }.freeze

  # FR → clés stables
  def up
    Child.reset_column_information

    Child.find_each do |child|
      # Couleur de cheveux : lookup insensible à la casse, sinon on garde tel quel
      if child.hair_color.present?
        child.hair_color = HAIR_FR_TO_KEY.fetch(child.hair_color.to_s.strip.downcase, child.hair_color)
      end

      # Couleur des yeux
      if child.eye_color.present?
        child.eye_color = EYES_FR_TO_KEY.fetch(child.eye_color.to_s.strip.downcase, child.eye_color)
      end

      # Teinte de peau
      if child.skin_tone.present?
        child.skin_tone = SKIN_FR_TO_KEY.fetch(child.skin_tone.to_s.strip.downcase, child.skin_tone)
      end

      # Traits : on mappe puis on filtre les traits obsolètes (nil = non reconnu)
      if child.personality_traits.present?
        child.personality_traits = child.personality_traits
          .map { |t| TRAITS_FR_TO_KEY[t.to_s.strip.downcase] }
          .compact
          .uniq
      end

      # save(validate: false) : on contourne la validation de consentement
      # parental (on: :create) qui n'a pas de sens sur une mise à jour de données
      child.save!(validate: false)
    end
  end

  # Clés stables → FR (best-effort, données réversibles)
  def down
    Child.reset_column_information

    Child.find_each do |child|
      child.hair_color = HAIR_KEY_TO_FR.fetch(child.hair_color.to_s, child.hair_color) if child.hair_color.present?
      child.eye_color  = EYES_KEY_TO_FR.fetch(child.eye_color.to_s, child.eye_color)   if child.eye_color.present?
      child.skin_tone  = SKIN_KEY_TO_FR.fetch(child.skin_tone.to_s, child.skin_tone)   if child.skin_tone.present?

      if child.personality_traits.present?
        child.personality_traits = child.personality_traits
          .map { |t| TRAITS_KEY_TO_FR.fetch(t.to_s, t) }
          .uniq
      end

      child.save!(validate: false)
    end
  end
end
