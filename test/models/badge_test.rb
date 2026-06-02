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
    assert badge.errors[:name].any?, "name devrait être obligatoire"
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
    assert badge.errors[:condition_key].any?, "condition_key devrait être obligatoire"
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

  # ===========================================================
  # SECTION 8 — Badges de progression avancés (20/30/50/100)
  # ===========================================================

  # Vérifie que twenty_stories est attribué après 20 histoires
  # Cas : exactement 20 histoires completed
  # Pourquoi : badge de progression intermédiaire pour les utilisateurs assidus
  test "check_and_award attribue twenty_stories après 20 histoires completed" do
    # Arrange
    user = User.create!(email: "vingt@example.com", password: "password123",
                        first_name: "Vingt", last_name: "Histoires")
    child = user.children.create!(name: "Héros", age: 7)
    20.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c") }

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "twenty_stories"),
           "Le badge twenty_stories devrait être attribué après 20 histoires"
  end

  # Vérifie que twenty_stories n'est PAS attribué avec 19 histoires
  # Cas : juste en dessous du seuil
  # Pourquoi : edge case strict — la condition est >= 20
  test "check_and_award n'attribue pas twenty_stories avec 19 histoires" do
    # Arrange
    user = User.create!(email: "dix_neuf@example.com", password: "password123",
                        first_name: "Dix", last_name: "Neuf")
    child = user.children.create!(name: "Héros", age: 7)
    19.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c") }

    # Act
    Badge.check_and_award(user)

    # Assert
    assert_not user.badges.exists?(condition_key: "twenty_stories"),
               "twenty_stories ne devrait pas être attribué avec seulement 19 histoires"
  end

  # ===========================================================
  # SECTION 9 — Badges Univers (3 histoires dans un thème)
  # ===========================================================

  # Vérifie que space_explorer est attribué après 3 histoires dans l'univers space
  # Cas : 3 histoires completed avec world_theme "space"
  # Pourquoi : récompense la fidélité à un univers particulier
  test "check_and_award attribue space_explorer après 3 histoires space" do
    # Arrange
    user = User.create!(email: "espace@example.com", password: "password123",
                        first_name: "Astro", last_name: "Naute")
    child = user.children.create!(name: "Fusée", age: 6)
    3.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c", world_theme: "space") }

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "space_explorer"),
           "Le badge space_explorer devrait être attribué après 3 histoires dans l'univers space"
  end

  # Vérifie que space_explorer n'est PAS attribué avec seulement 2 histoires space
  # Cas : en dessous du seuil de 3
  test "check_and_award n'attribue pas space_explorer avec 2 histoires space" do
    # Arrange
    user = User.create!(email: "espace2@example.com", password: "password123",
                        first_name: "Quasi", last_name: "Astro")
    child = user.children.create!(name: "Fusée", age: 6)
    2.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c", world_theme: "space") }

    # Act
    Badge.check_and_award(user)

    # Assert
    assert_not user.badges.exists?(condition_key: "space_explorer"),
               "space_explorer ne devrait pas être attribué avec seulement 2 histoires space"
  end

  # Vérifie que world_traveler est attribué quand les 5 univers ont chacun 1 histoire
  # Cas : 1 histoire dans chacun des 5 univers disponibles
  # Pourquoi : badge d'exploration complète — tous les univers visités au moins une fois
  test "check_and_award attribue world_traveler avec 1 histoire dans chaque univers" do
    # Arrange
    user = User.create!(email: "voyageur@example.com", password: "password123",
                        first_name: "Grand", last_name: "Voyageur")
    child = user.children.create!(name: "Explorateur", age: 8)

    # Une histoire dans chacun des 5 univers disponibles
    %w[space dinos princesses pirates animals].each_with_index do |theme, i|
      child.stories.create!(status: :completed, title: "H#{i}", content: "c", world_theme: theme)
    end

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "world_traveler"),
           "Le badge world_traveler devrait être attribué quand les 5 univers sont explorés"
  end

  # Vérifie que world_traveler n'est PAS attribué si un univers manque
  # Cas : 4 univers sur 5 seulement
  # Pourquoi : tous les 5 univers sont obligatoires pour ce badge
  test "check_and_award n'attribue pas world_traveler si un univers manque" do
    # Arrange
    user = User.create!(email: "presque_voyageur@example.com", password: "password123",
                        first_name: "Presque", last_name: "Voyageur")
    child = user.children.create!(name: "Explorateur", age: 8)

    # Seulement 4 univers (animals manquant)
    %w[space dinos princesses pirates].each_with_index do |theme, i|
      child.stories.create!(status: :completed, title: "H#{i}", content: "c", world_theme: theme)
    end

    # Act
    Badge.check_and_award(user)

    # Assert
    assert_not user.badges.exists?(condition_key: "world_traveler"),
               "world_traveler ne devrait pas être attribué si un univers n'a pas été exploré"
  end

  # ===========================================================
  # SECTION 10 — Badge saga_starter (suite d'histoire)
  # ===========================================================

  # Vérifie que saga_starter est attribué quand une histoire a un parent
  # Cas : une histoire avec parent_story_id renseigné
  # Pourquoi : récompense la création d'une suite — encourage la narration continue
  test "check_and_award attribue saga_starter quand une histoire a un parent" do
    # Arrange
    user = User.create!(email: "saga@example.com", password: "password123",
                        first_name: "Saga", last_name: "Starter")
    child = user.children.create!(name: "Héros", age: 7)

    # Épisode 1 — l'histoire originale
    ep1 = child.stories.create!(status: :completed, title: "Épisode 1", content: "début")

    # Épisode 2 — la suite, avec parent_story_id pointant vers ep1
    child.stories.create!(status: :completed, title: "Épisode 2", content: "suite",
                          parent_story_id: ep1.id)

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "saga_starter"),
           "Le badge saga_starter devrait être attribué quand une histoire a un parent"
  end

  # Vérifie que saga_starter n'est PAS attribué sans saga
  # Cas : toutes les histoires sont des épisodes 1 (pas de parent)
  test "check_and_award n'attribue pas saga_starter sans histoire avec parent" do
    # Arrange
    user = User.create!(email: "pas_saga@example.com", password: "password123",
                        first_name: "Solo", last_name: "Stories")
    child = user.children.create!(name: "Héros", age: 7)

    # Seulement des histoires indépendantes — aucun parent
    3.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c") }

    # Act
    Badge.check_and_award(user)

    # Assert
    assert_not user.badges.exists?(condition_key: "saga_starter"),
               "saga_starter ne devrait pas être attribué sans suite d'histoire"
  end

  # ===========================================================
  # SECTION 11 — Badges Styles (ghibli_fan, cinematic_pro)
  # ===========================================================

  # Vérifie que ghibli_fan est attribué après 5 histoires en style ghibli
  # Cas : 5 histoires completed avec image_style "ghibli"
  # Pourquoi : récompense la fidélité au style Studio Ghibli
  test "check_and_award attribue ghibli_fan après 5 histoires ghibli" do
    # Arrange
    user = User.create!(email: "ghibli@example.com", password: "password123",
                        first_name: "Ghibli", last_name: "Fan")
    child = user.children.create!(name: "Héros", age: 6)
    5.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c", image_style: "ghibli") }

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "ghibli_fan"),
           "Le badge ghibli_fan devrait être attribué après 5 histoires en style ghibli"
  end

  # Vérifie que cinematic_pro est attribué après 3 histoires en style cinematic
  # Cas : 3 histoires completed avec image_style "cinematic"
  # Pourquoi : récompense l'utilisation du style cinématique — badge spécifique au nouveau style
  test "check_and_award attribue cinematic_pro après 3 histoires cinematic" do
    # Arrange
    user = User.create!(email: "cinema@example.com", password: "password123",
                        first_name: "Cinema", last_name: "Pro")
    child = user.children.create!(name: "Réalisateur", age: 8)
    3.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c", image_style: "cinematic") }

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "cinematic_pro"),
           "Le badge cinematic_pro devrait être attribué après 3 histoires en style cinematic"
  end

  # Vérifie que style_explorer est attribué quand les 5 styles sont utilisés
  # Cas : 1 histoire dans chacun des 5 styles disponibles
  # Pourquoi : récompense l'exploration de tous les styles artistiques
  test "check_and_award attribue style_explorer avec 1 histoire dans chaque style" do
    # Arrange
    user = User.create!(email: "artiste@example.com", password: "password123",
                        first_name: "Artiste", last_name: "Complet")
    child = user.children.create!(name: "Peintre", age: 7)

    # Une histoire dans chacun des 5 styles disponibles
    %w[ghibli comics pixar watercolor cinematic].each_with_index do |style, i|
      child.stories.create!(status: :completed, title: "H#{i}", content: "c", image_style: style)
    end

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "style_explorer"),
           "Le badge style_explorer devrait être attribué quand les 5 styles sont utilisés"
  end

  # ===========================================================
  # SECTION 12 — Badges Valeurs éducatives supplémentaires
  # ===========================================================

  # Vérifie que courage_heart est attribué après 3 histoires avec valeur "courage"
  # Cas : 3 histoires avec educational_value: "courage"
  # Pourquoi : récompense l'apprentissage de la valeur courage
  test "check_and_award attribue courage_heart après 3 histoires courage" do
    # Arrange
    user = User.create!(email: "courage@example.com", password: "password123",
                        first_name: "Courage", last_name: "Heart")
    child = user.children.create!(name: "Brave", age: 5)
    3.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c", educational_value: "courage") }

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "courage_heart"),
           "Le badge courage_heart devrait être attribué après 3 histoires avec valeur courage"
  end

  # Vérifie que sharing_heart est attribué après 3 histoires avec valeur "sharing"
  # Cas : 3 histoires avec educational_value: "sharing"
  test "check_and_award attribue sharing_heart après 3 histoires sharing" do
    # Arrange
    user = User.create!(email: "sharing@example.com", password: "password123",
                        first_name: "Sharing", last_name: "Heart")
    child = user.children.create!(name: "Généreux", age: 5)
    3.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c", educational_value: "sharing") }

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "sharing_heart"),
           "Le badge sharing_heart devrait être attribué après 3 histoires avec valeur sharing"
  end

  # Vérifie que confidence_builder est attribué après 3 histoires avec valeur "confidence"
  # Cas : 3 histoires avec educational_value: "confidence"
  test "check_and_award attribue confidence_builder après 3 histoires confidence" do
    # Arrange
    user = User.create!(email: "confidence@example.com", password: "password123",
                        first_name: "Confi", last_name: "Builder")
    child = user.children.create!(name: "Confiant", age: 5)
    3.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c", educational_value: "confidence") }

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "confidence_builder"),
           "Le badge confidence_builder devrait être attribué après 3 histoires avec valeur confidence"
  end

  # ===========================================================
  # SECTION 13 — Badges Thème libre (free_spirit, imaginative)
  # ===========================================================

  # Vérifie que free_spirit est attribué dès la première histoire avec custom_theme
  # Cas : 1 histoire completed avec custom_theme renseigné (pas nil, pas vide)
  # Pourquoi : récompense la créativité personnelle — l'utilisateur invente son propre univers
  test "check_and_award attribue free_spirit après 1 histoire avec custom_theme" do
    # Arrange
    user = User.create!(email: "libre@example.com", password: "password123",
                        first_name: "Libre", last_name: "Spirit")
    child = user.children.create!(name: "Créatif", age: 7)
    child.stories.create!(status: :completed, title: "Mon univers", content: "c",
                          custom_theme: "Un robot qui vit dans les nuages")

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "free_spirit"),
           "Le badge free_spirit devrait être attribué après 1 histoire avec un thème personnalisé"
  end

  # Vérifie que imaginative est attribué après 5 histoires avec custom_theme
  # Cas : 5 histoires completed avec custom_theme renseigné
  test "check_and_award attribue imaginative après 5 histoires avec custom_theme" do
    # Arrange
    user = User.create!(email: "imaginatif@example.com", password: "password123",
                        first_name: "Grand", last_name: "Imaginatif")
    child = user.children.create!(name: "Rêveur", age: 8)
    5.times do |i|
      child.stories.create!(status: :completed, title: "H#{i}", content: "c",
                            custom_theme: "Univers inventé #{i}")
    end

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "imaginative"),
           "Le badge imaginative devrait être attribué après 5 histoires avec thème personnalisé"
  end

  # ===========================================================
  # SECTION 14 — Badges Durée (quick_tales, epic_reader)
  # ===========================================================

  # Vérifie que quick_tales est attribué après 5 histoires de 5 minutes
  # Cas : 5 histoires completed avec duration_minutes: 5
  # Pourquoi : récompense les sessions courtes et répétées
  test "check_and_award attribue quick_tales après 5 histoires de 5 minutes" do
    # Arrange
    user = User.create!(email: "rapide@example.com", password: "password123",
                        first_name: "Vite", last_name: "Fait")
    child = user.children.create!(name: "Express", age: 5)
    5.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c", duration_minutes: 5) }

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "quick_tales"),
           "Le badge quick_tales devrait être attribué après 5 histoires de 5 minutes"
  end

  # Vérifie que epic_reader est attribué dès la 1ère histoire de 15 minutes
  # Cas : 1 histoire completed avec duration_minutes: 15
  # Pourquoi : récompense le goût pour les grandes aventures — durée maximale
  test "check_and_award attribue epic_reader après 1 histoire de 15 minutes" do
    # Arrange
    user = User.create!(email: "epique@example.com", password: "password123",
                        first_name: "Lecteur", last_name: "Epique")
    child = user.children.create!(name: "Long", age: 9)
    child.stories.create!(status: :completed, title: "Grand épique", content: "c", duration_minutes: 15)

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "epic_reader"),
           "Le badge epic_reader devrait être attribué après 1 histoire de 15 minutes"
  end

  # ===========================================================
  # SECTION 15 — Badges Bibliothèque (collector, great_library)
  # ===========================================================

  # Vérifie que collector est attribué après 5 histoires sauvegardées
  # Cas : 5 histoires completed avec saved: true
  # Pourquoi : premier badge de bibliothèque — seuil inférieur à bookworm
  test "check_and_award attribue collector après 5 histoires sauvegardées" do
    # Arrange
    user = User.create!(email: "collectionneur@example.com", password: "password123",
                        first_name: "Collec", last_name: "Teur")
    child = user.children.create!(name: "Lecteur", age: 8)
    5.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c", saved: true) }

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "collector"),
           "Le badge collector devrait être attribué après 5 histoires sauvegardées"
  end

  # Vérifie que collector n'est PAS attribué avec seulement 4 histoires sauvegardées
  # Cas : juste en dessous du seuil de 5
  test "check_and_award n'attribue pas collector avec 4 histoires sauvegardées" do
    # Arrange
    user = User.create!(email: "presque_collect@example.com", password: "password123",
                        first_name: "Presque", last_name: "Collect")
    child = user.children.create!(name: "Lecteur", age: 8)
    4.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c", saved: true) }

    # Act
    Badge.check_and_award(user)

    # Assert
    assert_not user.badges.exists?(condition_key: "collector"),
               "collector ne devrait pas être attribué avec seulement 4 histoires sauvegardées"
  end

  # ===========================================================
  # SECTION 16 — Badge night_owl (heure de création)
  # ===========================================================

  # Vérifie que night_owl est attribué quand une histoire est créée après 21h
  # Cas : histoire completed avec created_at à 22h
  # Pourquoi : récompense les aventures nocturnes — condition basée sur l'heure PostgreSQL
  test "check_and_award attribue night_owl pour une histoire créée à 22h" do
    # Arrange
    user = User.create!(email: "nuit@example.com", password: "password123",
                        first_name: "Hibou", last_name: "Nocturne")
    child = user.children.create!(name: "Noctambule", age: 7)

    # Crée une histoire avec un created_at forcé à 22h00 aujourd'hui
    # Time.current.change modifie uniquement les composantes indiquées
    night_time = Time.current.change(hour: 22, min: 0, sec: 0)
    child.stories.create!(status: :completed, title: "Histoire de nuit", content: "c",
                          created_at: night_time)

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "night_owl"),
           "Le badge night_owl devrait être attribué pour une histoire créée à 22h"
  end

  # ===========================================================
  # SECTION 17 — Badge weekend_tales (histoires le week-end)
  # ===========================================================

  # Vérifie que weekend_tales est attribué après 3 histoires créées un samedi ou dimanche
  # Cas : 3 histoires created_at un samedi (DOW = 6 en PostgreSQL)
  # Pourquoi : récompense les aventures du week-end — condition basée sur le jour PostgreSQL
  test "check_and_award attribue weekend_tales après 3 histoires le week-end" do
    # Arrange
    user = User.create!(email: "weekend@example.com", password: "password123",
                        first_name: "Weekend", last_name: "Hero")
    child = user.children.create!(name: "Samedi", age: 7)

    # Trouve le prochain samedi à partir d'aujourd'hui
    # wday: 0=dim, 1=lun, ... 6=sam (convention Ruby, identique à PostgreSQL DOW)
    today = Date.today
    saturday = today + ((6 - today.wday) % 7)
    saturday_time = saturday.to_time.change(hour: 10)

    # Crée 3 histoires avec created_at forcé à un samedi
    3.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c", created_at: saturday_time) }

    # Act
    Badge.check_and_award(user)

    # Assert
    user.reload
    assert user.badges.exists?(condition_key: "weekend_tales"),
           "Le badge weekend_tales devrait être attribué après 3 histoires créées le week-end"
  end

  # Vérifie que weekend_tales n'est PAS attribué avec des histoires en semaine
  # Cas : 3 histoires créées un mercredi (DOW = 3)
  test "check_and_award n'attribue pas weekend_tales pour des histoires en semaine" do
    # Arrange
    user = User.create!(email: "semaine@example.com", password: "password123",
                        first_name: "Semaine", last_name: "Worker")
    child = user.children.create!(name: "Lundi", age: 7)

    # Trouve le prochain mercredi
    today = Date.today
    wednesday = today + ((3 - today.wday) % 7)
    wednesday_time = wednesday.to_time.change(hour: 10)

    # 3 histoires un mercredi — pas le week-end
    3.times { |i| child.stories.create!(status: :completed, title: "H#{i}", content: "c", created_at: wednesday_time) }

    # Act
    Badge.check_and_award(user)

    # Assert
    assert_not user.badges.exists?(condition_key: "weekend_tales"),
               "weekend_tales ne devrait pas être attribué pour des histoires créées en semaine"
  end
end
