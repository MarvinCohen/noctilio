# Test du modèle Badge
# Ce fichier vérifie la logique d'attribution des badges :
# - La méthode de classe check_and_award attribue les bons badges selon les conditions
# - Les doublons sont évités
# - Chaque condition de badge est testée indépendamment
require "test_helper"

class BadgeTest < ActiveSupport::TestCase

  # ===========================================================
  # SECTION 1 — VALIDATIONS
  # ===========================================================

  # Vérifie qu'un badge sans nom est invalide
  # Cas : name manquant
  # Pourquoi : le nom est affiché à l'utilisateur dans la salle des trophées
  test "un badge sans nom est invalide" do
    # Arrange
    badge = Badge.new(condition_key: "test_key")

    # Act
    badge.valid?

    # Assert
    assert_includes badge.errors[:name], "can't be blank"
  end

  # Vérifie qu'un badge sans condition_key est invalide
  # Cas : condition_key manquant
  # Pourquoi : condition_key est la clé qui identifie la logique à vérifier dans check_and_award
  test "un badge sans condition_key est invalide" do
    # Arrange
    badge = Badge.new(name: "Test Badge")

    # Act
    badge.valid?

    # Assert
    assert_includes badge.errors[:condition_key], "can't be blank"
  end

  # Vérifie que deux badges ne peuvent pas avoir la même condition_key
  # Cas : doublon de condition_key
  # Pourquoi : l'unicité est essentielle — check_and_award cherche par condition_key
  test "deux badges avec la même condition_key sont refusés" do
    # Arrange — first_story existe déjà dans les fixtures
    badge = Badge.new(name: "Doublon", condition_key: "first_story")

    # Act
    badge.valid?

    # Assert
    assert badge.errors[:condition_key].any?,
           "condition_key doit être unique — un doublon devrait être refusé"
  end

  # ===========================================================
  # SECTION 2 — Badge first_story (1ère histoire)
  # ===========================================================

  # Vérifie que le badge first_story est attribué après 1 histoire completed
  # Cas : utilisateur avec exactement 1 histoire completed, pas encore de badge
  # Pourquoi : c'est le premier badge du parcours — encourage les nouveaux utilisateurs
  test "check_and_award attribue first_story après 1 histoire completed" do
    # Arrange — on crée un utilisateur frais sans badge, avec 1 histoire completed
    user = User.create!(
      email: "nouveau@example.com",
      password: "password123",
      first_name: "Nouveau",
      last_name: "User"
    )
    child = user.children.create!(name: "Petit", age: 4)
    child.stories.create!(status: :completed, title: "Ma première histoire", content: "Il était une fois...")

    # Vérifie que l'utilisateur n'a pas encore le badge
    assert_not user.badges.exists?(condition_key: "first_story"),
               "Pré-condition : l'utilisateur ne doit pas encore avoir le badge first_story"

    # Act — appelle la méthode qui vérifie et attribue les badges
    Badge.check_and_award(user)

    # Assert — le badge first_story doit maintenant être attribué
    user.reload   # Recharge l'utilisateur depuis la base pour avoir les données fraîches
    assert user.badges.exists?(condition_key: "first_story"),
           "Le badge first_story devrait être attribué après 1 histoire completed"
  end

  # Vérifie que first_story n'est PAS attribué si aucune histoire n'est completed
  # Cas : utilisateur avec 1 histoire pending (pas encore terminée)
  # Pourquoi : seules les histoires completed comptent — pas les pending ou failed
  test "check_and_award n'attribue pas first_story si aucune histoire n'est completed" do
    # Arrange — utilisateur avec 1 histoire pending seulement
    user = User.create!(
      email: "sans_histoire@example.com",
      password: "password123",
      first_name: "Sans",
      last_name: "Histoire"
    )
    child = user.children.create!(name: "Enfant", age: 5)
    child.stories.create!(status: :pending)

    # Act
    Badge.check_and_award(user)

    # Assert — pas de badge car pas d'histoire completed
    assert_not user.badges.exists?(condition_key: "first_story"),
               "first_story ne devrait pas être attribué si aucune histoire n'est completed"
  end

  # ===========================================================
  # SECTION 3 — Badge five_stories (5 histoires)
  # ===========================================================

  # Vérifie que five_stories est attribué après 5 histoires completed
  # Cas : utilisateur avec exactement 5 histoires completed
  # Pourquoi : badge de progression intermédiaire — valide l'engagement de l'utilisateur
  test "check_and_award attribue five_stories après 5 histoires completed" do
    # Arrange — crée un utilisateur avec 5 histoires completed
    user = User.create!(
      email: "cinq_histoires@example.com",
      password: "password123",
      first_name: "Cinq",
      last_name: "Histoires"
    )
    child = user.children.create!(name: "Héros", age: 7)

    # Crée 5 histoires completed
    5.times do |i|
      child.stories.create!(
        status: :completed,
        title: "Histoire #{i + 1}",
        content: "Contenu de l'histoire #{i + 1}"
      )
    end

    # Act
    Badge.check_and_award(user)

    # Assert — five_stories doit être attribué
    user.reload
    assert user.badges.exists?(condition_key: "five_stories"),
           "Le badge five_stories devrait être attribué après 5 histoires completed"
  end

  # Vérifie que five_stories n'est PAS attribué avec seulement 4 histoires
  # Cas : limite de 4 histoires — juste en dessous du seuil
  # Pourquoi : edge case — vérifie que la condition >= 5 est strictement respectée
  test "check_and_award n'attribue pas five_stories avec seulement 4 histoires" do
    # Arrange — crée un utilisateur avec 4 histoires completed (pas assez)
    user = User.create!(
      email: "quatre_histoires@example.com",
      password: "password123",
      first_name: "Quatre",
      last_name: "Histoires"
    )
    child = user.children.create!(name: "Presque", age: 6)

    4.times do |i|
      child.stories.create!(
        status: :completed,
        title: "Histoire #{i + 1}",
        content: "Contenu"
      )
    end

    # Act
    Badge.check_and_award(user)

    # Assert — 4 < 5 donc five_stories ne doit pas être attribué
    assert_not user.badges.exists?(condition_key: "five_stories"),
               "five_stories ne devrait pas être attribué avec seulement 4 histoires"
  end

  # ===========================================================
  # SECTION 4 — Pas de doublons
  # ===========================================================

  # Vérifie que check_and_award ne crée pas de doublon si le badge est déjà attribué
  # Cas : Marie a déjà first_story dans les fixtures, on rappelle check_and_award
  # Pourquoi : rule métier critique — un badge ne peut être obtenu qu'une seule fois
  test "check_and_award ne crée pas de doublon si le badge est déjà attribué" do
    # Arrange — Marie a déjà le badge first_story (voir fixtures/user_badges.yml)
    user = users(:marie)

    # Compte le nombre de user_badges avant
    count_before = user.user_badges.count

    # Act — appelle check_and_award alors que first_story est déjà là
    Badge.check_and_award(user)

    # Assert — le nombre de badges ne doit pas avoir augmenté pour first_story
    user.reload
    count_after = user.user_badges.count

    # count_after peut être supérieur si d'autres badges ont été gagnés (ex: five_stories)
    # mais first_story ne doit PAS avoir créé un deuxième UserBadge
    first_story_count = user.user_badges.joins(:badge).where(badges: { condition_key: "first_story" }).count
    assert_equal 1, first_story_count,
                 "Le badge first_story ne devrait exister qu'une seule fois — pas de doublon"
  end

  # Vérifie que la validation d'unicité sur UserBadge bloque les doublons en base
  # Cas : tentative de créer deux UserBadge avec le même user + badge
  # Pourquoi : double protection — modèle ET index unique en base
  test "créer deux fois le même UserBadge lève une erreur de validation" do
    # Arrange — Marie a déjà first_story
    user = users(:marie)
    badge = badges(:first_story)

    # Tente de créer un doublon en base
    duplicate = UserBadge.new(user: user, badge: badge, earned_at: Time.current)

    # Act
    duplicate.valid?

    # Assert — l'erreur d'unicité doit être présente
    assert duplicate.errors[:user_id].any?,
           "Créer un UserBadge en doublon devrait échouer à la validation"
  end

  # ===========================================================
  # SECTION 5 — Badge ten_stories (10 histoires)
  # ===========================================================

  # Vérifie que ten_stories est attribué après 10 histoires completed
  # Cas : utilisateur avec exactement 10 histoires completed
  # Pourquoi : badge de fidélité — récompense les utilisateurs très actifs
  test "check_and_award attribue ten_stories après 10 histoires completed" do
    # Arrange — crée 10 histoires completed pour un nouvel utilisateur
    user = User.create!(
      email: "dix_histoires@example.com",
      password: "password123",
      first_name: "Dix",
      last_name: "Histoires"
    )
    child = user.children.create!(name: "Champion", age: 8)

    10.times do |i|
      child.stories.create!(
        status: :completed,
        title: "Histoire #{i + 1}",
        content: "Contenu #{i + 1}"
      )
    end

    # Act
    Badge.check_and_award(user)

    # Assert — ten_stories doit être attribué
    user.reload
    assert user.badges.exists?(condition_key: "ten_stories"),
           "Le badge ten_stories devrait être attribué après 10 histoires completed"
  end

  # ===========================================================
  # SECTION 6 — Badge kind_heart (valeur kindness × 3)
  # ===========================================================

  # Vérifie que kind_heart est attribué après 3 histoires avec educational_value "kindness"
  # Cas : 3 histoires avec kindness
  # Pourquoi : encourage les parents à choisir des valeurs éducatives bienveillantes
  test "check_and_award attribue kind_heart après 3 histoires kindness" do
    # Arrange
    user = User.create!(
      email: "kindness@example.com",
      password: "password123",
      first_name: "Kind",
      last_name: "Heart"
    )
    child = user.children.create!(name: "Gentil", age: 5)

    # Crée 3 histoires avec educational_value: "kindness"
    # Note : check_and_award regarde toutes les histoires (completed ou non)
    3.times do |i|
      child.stories.create!(
        status: :completed,
        title: "Histoire gentille #{i + 1}",
        content: "Contenu",
        educational_value: "kindness"
      )
    end

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "kind_heart"),
           "Le badge kind_heart devrait être attribué après 3 histoires avec valeur kindness"
  end

  # Vérifie que kind_heart n'est pas attribué avec seulement 2 histoires kindness
  # Cas : juste en dessous du seuil de 3
  # Pourquoi : edge case — la condition est >= 3, pas >= 2
  test "check_and_award n'attribue pas kind_heart avec seulement 2 histoires kindness" do
    # Arrange
    user = User.create!(
      email: "presque_kindness@example.com",
      password: "password123",
      first_name: "Presque",
      last_name: "Kind"
    )
    child = user.children.create!(name: "Bientot", age: 5)

    # Seulement 2 histoires kindness — pas assez
    2.times do |i|
      child.stories.create!(
        status: :completed,
        title: "Histoire #{i + 1}",
        content: "Contenu",
        educational_value: "kindness"
      )
    end

    # Act
    Badge.check_and_award(user)

    # Assert
    assert_not user.badges.exists?(condition_key: "kind_heart"),
               "kind_heart ne devrait pas être attribué avec seulement 2 histoires kindness"
  end

  # ===========================================================
  # SECTION 7 — Badge bookworm (10 histoires saved + completed)
  # ===========================================================

  # Vérifie que bookworm est attribué après 10 histoires completed ET sauvegardées
  # Cas : 10 histoires completed avec saved: true
  # Pourquoi : récompense l'engagement long terme — relire et garder ses histoires
  test "check_and_award attribue bookworm après 10 histoires saved et completed" do
    # Arrange
    user = User.create!(
      email: "bookworm@example.com",
      password: "password123",
      first_name: "Grand",
      last_name: "Lecteur"
    )
    child = user.children.create!(name: "Lecteur", age: 9)

    # Crée 10 histoires completed ET sauvegardées
    10.times do |i|
      child.stories.create!(
        status: :completed,
        title: "Histoire #{i + 1}",
        content: "Contenu",
        saved: true
      )
    end

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "bookworm"),
           "Le badge bookworm devrait être attribué après 10 histoires completed et sauvegardées"
  end
end
