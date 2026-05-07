# Test du modèle Child
# Ce fichier vérifie les règles métier du modèle Child :
# validations de nom et d'âge, scopes, et méthodes de description
# utilisées pour construire les prompts IA (avatar_description, image_description).
require "test_helper"

class ChildTest < ActiveSupport::TestCase

  # ===========================================================
  # SECTION 1 — VALIDATIONS
  # ===========================================================

  # Vérifie qu'un enfant avec des données valides est accepté
  # Cas : données minimales correctes (name + age + user)
  # Pourquoi : s'assurer que notre fixture de base est cohérente
  test "un enfant valide est sauvegardé sans erreur" do
    # Arrange — charge un enfant déjà bien configuré depuis les fixtures
    child = children(:leo)

    # Assert — aucune erreur de validation
    assert child.valid?, "Léo devrait être valide mais a des erreurs : #{child.errors.full_messages}"
  end

  # Vérifie qu'un enfant sans nom est invalide
  # Cas : name manquant
  # Pourquoi : le nom est obligatoire — il est injecté dans tous les prompts IA
  test "un enfant sans nom est invalide" do
    # Arrange
    child = children(:leo)
    child.name = nil

    # Act
    child.valid?

    # Assert — une erreur doit être présente sur name
    assert child.errors[:name].any?, "name devrait être obligatoire"
  end

  # Vérifie qu'un nom trop court (1 caractère) est refusé
  # Cas : name < 2 caractères
  # Pourquoi : la validation impose minimum: 2 — "A" serait un prénom invalide
  test "un nom d'un seul caractère est invalide" do
    # Arrange
    child = children(:leo)
    child.name = "A"

    # Act
    child.valid?

    # Assert
    assert child.errors[:name].any?,
           "Un nom d'un seul caractère devrait être refusé (minimum: 2)"
  end

  # Vérifie qu'un nom trop long (> 50 caractères) est refusé
  # Cas : name > 50 caractères
  # Pourquoi : la validation impose maximum: 50 pour éviter les débordements d'affichage
  test "un nom de plus de 50 caractères est invalide" do
    # Arrange
    child = children(:leo)
    child.name = "A" * 51  # 51 caractères — dépasse la limite

    # Act
    child.valid?

    # Assert
    assert child.errors[:name].any?,
           "Un nom de 51 caractères devrait être refusé (maximum: 50)"
  end

  # Vérifie qu'un enfant sans âge est invalide
  # Cas : age manquant
  # Pourquoi : l'âge est obligatoire — il détermine le niveau de langage des histoires
  test "un enfant sans âge est invalide" do
    # Arrange
    child = children(:leo)
    child.age = nil

    # Act
    child.valid?

    # Assert
    assert child.errors[:age].any?, "age devrait être obligatoire"
  end

  # Vérifie qu'un âge de 0 est refusé
  # Cas : age = 0 — en dessous du seuil minimum (greater_than: 0)
  # Pourquoi : un enfant de 0 an ne lit pas d'histoires, et le prompt IA serait incohérent
  test "un enfant avec un âge de 0 est invalide" do
    # Arrange
    child = children(:leo)
    child.age = 0

    # Act
    child.valid?

    # Assert
    assert child.errors[:age].any?,
           "L'âge 0 devrait être refusé (greater_than: 0)"
  end

  # Vérifie qu'un âge de 16 ou plus est refusé
  # Cas : age = 16 — dépasse la limite (less_than: 16)
  # Pourquoi : Noctilio cible les enfants de moins de 16 ans
  test "un enfant avec un âge de 16 est invalide" do
    # Arrange
    child = children(:leo)
    child.age = 16

    # Act
    child.valid?

    # Assert
    assert child.errors[:age].any?,
           "L'âge 16 devrait être refusé (less_than: 16)"
  end

  # Vérifie qu'un âge décimal est refusé
  # Cas : age = 5.5 — l'age doit être un entier (only_integer: true)
  # Pourquoi : les prompts IA utilisent "X ans" — un décimal n'a pas de sens
  test "un enfant avec un âge décimal est invalide" do
    # Arrange
    child = children(:leo)
    child.age = 5.5

    # Act
    child.valid?

    # Assert
    assert child.errors[:age].any?,
           "Un âge décimal devrait être refusé (only_integer: true)"
  end

  # ===========================================================
  # SECTION 2 — SCOPES
  # ===========================================================

  # Vérifie que le scope `ordered` trie par created_at décroissant
  # Cas : plusieurs enfants avec des dates différentes
  # Pourquoi : l'interface affiche les enfants du plus récent au plus ancien
  test "scope ordered trie les enfants du plus récent au plus ancien" do
    # Act — récupère les enfants de Marie dans l'ordre
    kids = users(:marie).children.ordered

    # Assert — le premier enfant doit être le plus récent
    if kids.size >= 2
      assert kids.first.created_at >= kids.second.created_at,
             "ordered devrait trier du plus récent au plus ancien"
    else
      # Pas assez d'enfants pour tester le tri — on vérifie que le scope s'exécute
      assert_kind_of ActiveRecord::Relation, kids
    end
  end

  # ===========================================================
  # SECTION 3 — MÉTHODE avatar_description
  # ===========================================================

  # Vérifie que avatar_description contient au minimum le nom et l'âge
  # Cas : enfant sans attributs optionnels (pas de couleur de cheveux, etc.)
  # Pourquoi : c'est le contenu minimal injecté dans le prompt narratif IA
  test "avatar_description contient le nom et l'âge de l'enfant" do
    # Arrange
    child = children(:leo)

    # Act
    description = child.avatar_description

    # Assert — le nom et l'âge doivent apparaître dans la description
    assert_includes description, child.name,
                    "avatar_description devrait contenir le nom de l'enfant"
    assert_includes description, child.age.to_s,
                    "avatar_description devrait contenir l'âge de l'enfant"
  end

  # Vérifie que avatar_description inclut la couleur de cheveux si elle est renseignée
  # Cas : enfant avec hair_color défini
  # Pourquoi : les attributs physiques garantissent la cohérence des illustrations
  test "avatar_description inclut la couleur de cheveux si renseignée" do
    # Arrange — crée un enfant temporaire avec une couleur de cheveux
    user = users(:marie)
    child = user.children.build(name: "Alice", age: 7, hair_color: "roux")

    # Act
    description = child.avatar_description

    # Assert — la couleur de cheveux doit être dans la description
    assert_includes description, "roux",
                    "avatar_description devrait inclure la couleur de cheveux"
  end

  # Vérifie que avatar_description inclut les hobbies au format "qui adore X et Y"
  # Cas : enfant avec plusieurs hobbies définis
  # Pourquoi : les hobbies enrichissent le récit et rendent l'histoire plus personnalisée
  test "avatar_description inclut les hobbies sous forme 'qui adore ...'" do
    # Arrange — crée un enfant avec des hobbies
    user = users(:marie)
    child = user.children.build(name: "Tom", age: 8, hobbies: ["foot", "dessin"])

    # Act
    description = child.avatar_description

    # Assert — le mot "adore" doit être présent (format "qui adore X et Y")
    assert_includes description, "adore",
                    "avatar_description devrait inclure les hobbies avec 'qui adore'"
    assert_includes description, "foot",   "avatar_description devrait contenir 'foot'"
    assert_includes description, "dessin", "avatar_description devrait contenir 'dessin'"
  end

  # ===========================================================
  # SECTION 4 — MÉTHODE image_description
  # ===========================================================

  # Vérifie que image_description contient le nom et l'âge en anglais
  # Cas : enfant garçon de 6 ans — description pour les modèles de diffusion
  # Pourquoi : les modèles FLUX/DALL-E répondent mieux aux descriptions en anglais
  test "image_description contient le nom, l'âge et le genre en anglais" do
    # Arrange
    child = children(:leo)  # Léo, garçon, 6 ans

    # Act
    description = child.image_description

    # Assert — le nom et l'âge doivent être présents
    assert_includes description, "Léo",     "image_description devrait contenir le nom"
    assert_includes description, "6",       "image_description devrait contenir l'âge"
    assert_includes description, "boy",     "image_description devrait contenir 'boy' pour un garçon"
  end

  # Vérifie que image_description traduit "vert" en "green eyes" pour les yeux
  # Cas : enfant avec eye_color "vert" — doit être traduit en anglais
  # Pourquoi : les modèles de diffusion comprennent mieux "green eyes" que "yeux vert"
  test "image_description traduit les yeux verts en 'green eyes'" do
    # Arrange — crée un enfant avec des yeux verts
    user = users(:marie)
    child = user.children.build(name: "Iris", age: 6, eye_color: "vert", gender: "girl")

    # Act
    description = child.image_description

    # Assert — "green eyes" doit être présent (pas "vert eyes")
    assert_includes description, "green eyes",
                    "image_description devrait traduire 'vert' en 'green eyes'"
  end

  # Vérifie que image_description traduit les cheveux blonds en "blonde hair"
  # Cas : hair_color contient "blond"
  # Pourquoi : les modèles de diffusion ont un meilleur rendu avec le terme anglais précis
  test "image_description traduit les cheveux blonds en 'blonde hair'" do
    # Arrange
    user = users(:marie)
    child = user.children.build(name: "Clara", age: 5, hair_color: "blond", gender: "girl")

    # Act
    description = child.image_description

    # Assert
    assert_includes description, "blonde hair",
                    "image_description devrait produire 'blonde hair' pour les cheveux blonds"
  end

  # ===========================================================
  # SECTION 5 — ASSOCIATIONS
  # ===========================================================

  # Vérifie que la suppression d'un enfant supprime ses histoires en cascade
  # Cas : dependent: :destroy sur has_many :stories
  # Pourquoi : pas d'histoires orphelines en base quand un enfant est supprimé
  test "supprimer un enfant supprime ses histoires en cascade" do
    # Arrange — crée un enfant temporaire avec une histoire
    user = users(:marie)
    temp_child = user.children.create!(name: "Temporaire", age: 4)
    story = temp_child.stories.create!(status: :pending)
    story_id = story.id

    # Act — supprime l'enfant
    temp_child.destroy

    # Assert — l'histoire doit avoir été supprimée automatiquement
    assert_nil Story.find_by(id: story_id),
               "L'histoire devrait être supprimée quand l'enfant est supprimé (dependent: :destroy)"
  end
end
