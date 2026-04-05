# Test du modèle Story
# Ce fichier vérifie toutes les règles métier du modèle Story :
# validations, enum de statut, scopes, et méthodes métier.
require "test_helper"

class StoryTest < ActiveSupport::TestCase

  # ===========================================================
  # SECTION 1 — VALIDATIONS
  # ===========================================================

  # Vérifie qu'une histoire valide peut être sauvegardée en base
  # Cas : données minimales correctes
  # Pourquoi : s'assurer que notre fixture est cohérente et que le modèle accepte les données valides
  test "une histoire valide est sauvegardée sans erreur" do
    # Arrange — on charge une histoire déjà bien configurée
    story = stories(:completed_saved)

    # Assert — pas d'erreur de validation
    assert story.valid?, "L'histoire devrait être valide mais a des erreurs : #{story.errors.full_messages}"
  end

  # Vérifie qu'une histoire sans enfant (child_id) est rejetée
  # Cas : child_id manquant
  # Pourquoi : une histoire doit toujours être rattachée à un enfant — règle métier fondamentale
  test "une histoire sans child_id est invalide" do
    # Arrange — construit une histoire sans enfant
    story = Story.new(status: :pending)

    # Act — déclenche les validations
    story.valid?

    # Assert — une erreur doit être présente sur child_id
    # Rails génère "can't be blank" (depuis validates presence: true sur child_id)
    # plutôt que "must exist" (qui vient du belongs_to quand l'ID est présent mais invalide)
    assert story.errors[:child_id].any?,
           "child_id devrait être obligatoire — une erreur doit être présente"
  end

  # Vérifie qu'une histoire sans status est rejetée
  # Cas : status nil
  # Pourquoi : le status contrôle tout le workflow de génération, il ne peut pas être absent
  test "une histoire sans status est invalide" do
    # Arrange — on prend un enfant existant pour isoler l'erreur sur status
    child = children(:leo)

    # On contourne l'enum en passant nil directement sur l'attribut
    story = Story.new(child: child)
    story.status = nil

    # Act
    story.valid?

    # Assert
    assert_includes story.errors[:status], "can't be blank",
                    "Le status devrait être obligatoire"
  end

  # Vérifie que duration_minutes n'accepte que les valeurs 5, 10, 15 (ou nil)
  # Cas : valeur hors liste (ex : 7)
  # Pourquoi : les durées sont des boutons radio prédéfinis — une valeur incorrecte ne doit pas passer
  test "duration_minutes invalide est rejeté" do
    # Arrange
    child = children(:leo)
    story = Story.new(child: child, status: :pending, duration_minutes: 7)

    # Act
    story.valid?

    # Assert — l'inclusion doit avoir rejeté la valeur 7
    assert story.errors[:duration_minutes].any?,
           "La durée 7 minutes devrait être invalide (autorisées : 5, 10, 15)"
  end

  # Vérifie que duration_minutes peut être nil (champ optionnel)
  # Cas : durée non renseignée
  # Pourquoi : allow_nil: true est déclaré dans la validation — on vérifie qu'il fonctionne
  test "duration_minutes nil est accepté" do
    # Arrange
    child = children(:leo)
    story = Story.new(child: child, status: :pending, duration_minutes: nil)

    # Act + Assert — nil ne doit pas générer d'erreur sur duration_minutes
    story.valid?
    assert_empty story.errors[:duration_minutes],
                 "La durée nil devrait être acceptée (champ optionnel)"
  end

  # ===========================================================
  # SECTION 2 — ENUM DE STATUT
  # ===========================================================

  # Vérifie que le statut "pending" (0) est bien reconnu
  # Cas : histoire tout juste créée, job pas encore lancé
  # Pourquoi : pending? est utilisé dans les vues pour afficher "en attente"
  test "statut pending est reconnu" do
    # Arrange
    story = stories(:pending_story)

    # Assert — la méthode pending? générée par l'enum doit retourner true
    assert story.pending?, "L'histoire devrait avoir le statut pending"
    # Vérifie aussi la valeur numérique en base (0)
    assert_equal 0, story.status_before_type_cast
  end

  # Vérifie que le statut "completed" (2) est bien reconnu
  # Cas : histoire entièrement générée, prête à être lue
  # Pourquoi : completed? est utilisé partout pour conditionner l'affichage du contenu
  test "statut completed est reconnu" do
    # Arrange
    story = stories(:completed_saved)

    # Assert
    assert story.completed?, "L'histoire devrait avoir le statut completed"
    assert_equal 2, story.status_before_type_cast
  end

  # Vérifie que le statut "failed" (3) est bien reconnu
  # Cas : l'IA a renvoyé une erreur pendant la génération
  # Pourquoi : failed? permet d'afficher un message d'erreur à l'utilisateur
  test "statut failed est reconnu" do
    # Arrange
    story = stories(:failed_story)

    # Assert
    assert story.failed?, "L'histoire devrait avoir le statut failed"
  end

  # Vérifie qu'on peut changer le statut d'une histoire
  # Cas : passage de pending à generating quand le job démarre
  # Pourquoi : le workflow entier repose sur ces transitions de statut
  test "on peut passer le statut de pending à generating" do
    # Arrange
    story = stories(:pending_story)
    assert story.pending?, "Pré-condition : l'histoire doit être pending au départ"

    # Act — simule le démarrage du job
    story.generating!

    # Assert — le statut doit avoir changé
    assert story.generating?, "Le statut devrait être generating après l'appel à generating!"
  end

  # ===========================================================
  # SECTION 3 — SCOPES
  # ===========================================================

  # Vérifie que le scope `completed` ne retourne que les histoires terminées
  # Cas : base avec des histoires dans plusieurs statuts
  # Pourquoi : ce scope est utilisé dans User#stories_this_month et les badges
  test "scope completed ne retourne que les histoires terminées" do
    # Act — récupère toutes les histoires completed de Léo
    completed = children(:leo).stories.completed

    # Assert — toutes les histoires retournées doivent être completed
    assert completed.any?, "Il devrait y avoir au moins une histoire completed"
    completed.each do |s|
      assert s.completed?, "Chaque histoire du scope completed doit être completed, pas #{s.status}"
    end
  end

  # Vérifie que le scope `recent` trie par date décroissante (la plus récente en premier)
  # Cas : plusieurs histoires avec des dates différentes
  # Pourquoi : la bibliothèque affiche les histoires dans l'ordre chronologique inversé
  test "scope recent trie par created_at décroissant" do
    # Act — récupère les histoires de Léo triées par recent
    stories_list = children(:leo).stories.recent

    # Assert — la date de la première histoire doit être >= à la suivante
    if stories_list.size >= 2
      assert stories_list.first.created_at >= stories_list.second.created_at,
             "Les histoires devraient être triées du plus récent au plus ancien"
    else
      # Pas assez d'histoires pour tester le tri — on vérifie juste que le scope s'exécute
      assert_kind_of ActiveRecord::Relation, stories_list
    end
  end

  # Vérifie que le scope `completed_recent` combine bien completed + recent
  # Cas : mélange d'histoires completed et pending
  # Pourquoi : c'est le scope utilisé dans StoriesController#index
  test "scope completed_recent ne retourne que des histoires completed et triées" do
    # Act
    results = children(:leo).stories.completed_recent

    # Assert 1 — toutes les histoires retournées sont completed
    results.each do |s|
      assert s.completed?, "completed_recent ne doit retourner que des histoires completed"
    end

    # Assert 2 — le tri est bien décroissant
    if results.size >= 2
      assert results.first.created_at >= results.second.created_at,
             "Les histoires devraient être triées du plus récent au plus ancien"
    end
  end

  # Vérifie que le scope `saved_stories` ne retourne que les histoires sauvegardées
  # Cas : histoires avec saved: true et saved: false
  # Pourquoi : la bibliothèque n'affiche que les histoires explicitement sauvegardées
  test "scope saved_stories ne retourne que les histoires avec saved: true" do
    # Act
    saved = children(:leo).stories.saved_stories

    # Assert — chaque histoire doit avoir saved == true
    saved.each do |s|
      assert s.saved?, "saved_stories ne devrait retourner que des histoires sauvegardées"
    end

    # Assert — l'histoire non sauvegardée ne doit pas apparaître
    non_saved_ids = children(:leo).stories.where(saved: false).pluck(:id)
    saved_ids = saved.pluck(:id)
    assert (saved_ids & non_saved_ids).empty?,
           "Les histoires non sauvegardées ne devraient pas apparaître"
  end

  # ===========================================================
  # SECTION 4 — MÉTHODES MÉTIER
  # ===========================================================

  # Vérifie que next_choice retourne le premier choix non effectué
  # Cas : histoire interactive avec un choix en attente
  # Pourquoi : utilisé dans has_pending_choice? et dans StoriesController#show
  test "next_choice retourne le prochain choix en attente" do
    # Arrange
    story = stories(:interactive_story)
    choice = story_choices(:pending_choice)

    # Act
    result = story.next_choice

    # Assert — doit trouver le choix non effectué
    assert_not_nil result, "next_choice devrait retourner un choix quand il en existe un"
    assert_nil result.chosen_option, "Le choix retourné ne doit pas encore avoir été effectué"
  end

  # Vérifie que next_choice retourne nil quand tous les choix sont faits
  # Cas : histoire interactive mais tous les choix ont chosen_option renseigné
  # Pourquoi : la vue doit savoir quand l'aventure interactive est terminée
  test "next_choice retourne nil si tous les choix sont faits" do
    # Arrange — on marque le choix comme effectué
    story = stories(:interactive_story)
    story.story_choices.update_all(chosen_option: "a")

    # Act
    result = story.next_choice

    # Assert
    assert_nil result, "next_choice devrait retourner nil quand tous les choix sont faits"
  end

  # Vérifie que has_pending_choice? retourne true si un choix est en attente
  # Cas : histoire interactive avec chosen_option nil
  # Pourquoi : utilisé pour afficher ou masquer les boutons de choix dans la vue
  test "has_pending_choice? retourne true si un choix est en attente" do
    # Arrange
    story = stories(:interactive_story)

    # Assert — l'histoire est interactive et a un choix non effectué
    assert story.has_pending_choice?,
           "has_pending_choice? devrait retourner true quand un choix est en attente"
  end

  # Vérifie que has_pending_choice? retourne false pour une histoire non interactive
  # Cas : histoire standard sans mode interactif
  # Pourquoi : on ne doit pas afficher de boutons de choix pour les histoires normales
  test "has_pending_choice? retourne false pour une histoire non interactive" do
    # Arrange
    story = stories(:completed_saved)
    assert_not story.interactive?, "Pré-condition : l'histoire ne doit pas être interactive"

    # Assert
    assert_not story.has_pending_choice?,
               "has_pending_choice? devrait retourner false pour une histoire non interactive"
  end

  # Vérifie que world_emoji retourne le bon emoji selon l'univers
  # Cas : univers "space"
  # Pourquoi : affiché dans les titres et cartes d'histoires
  test "world_emoji retourne le bon emoji pour l'univers space" do
    # Arrange
    child = children(:leo)
    story = child.stories.build(world_theme: "space", status: :pending)

    # Assert
    assert_equal "🚀", story.world_emoji
  end

  # Vérifie que world_emoji retourne ✨ pour un univers inconnu ou nil
  # Cas : histoire avec custom_theme, pas de world_theme prédéfini
  # Pourquoi : valeur par défaut quand l'utilisateur a décrit son propre univers
  test "world_emoji retourne ✨ pour un univers inconnu" do
    # Arrange
    child = children(:leo)
    story = child.stories.build(world_theme: nil, status: :pending)

    # Assert
    assert_equal "✨", story.world_emoji
  end

  # Vérifie que all_children retourne l'enfant principal + les extras
  # Cas : histoire avec un seul enfant (pas d'extra)
  # Pourquoi : utilisé dans les prompts IA pour décrire tous les héros
  test "all_children retourne au minimum l'enfant principal" do
    # Arrange
    story = stories(:completed_saved)

    # Act
    result = story.all_children

    # Assert — doit contenir au moins l'enfant principal
    assert_includes result, story.child,
                    "all_children doit toujours inclure l'enfant principal"
  end
end
