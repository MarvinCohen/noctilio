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
    # On vérifie la présence d'une erreur sur status, sans dépendre du libellé traduit
    assert story.errors[:status].any?, "Le status devrait être obligatoire"
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
  # Pourquoi : ce scope est utilisé dans User#stories_this_week et les badges
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

  # Vérifie que le style d'image "cinematic" est accepté comme valeur valide
  # Cas : nouveau style ajouté — il doit passer la validation inclusion
  # Pourquoi : cinematic est le 5ème style — il doit être dans la liste autorisée
  test "image_style cinematic est accepté par la validation" do
    # Arrange
    child = children(:leo)
    story = Story.new(child: child, status: :pending, image_style: "cinematic")

    # Act
    story.valid?

    # Assert — aucune erreur ne doit porter sur image_style
    assert_empty story.errors[:image_style],
                 "Le style cinematic devrait être valide — il fait partie des 5 styles autorisés"
  end

  # Vérifie qu'un style inconnu est refusé par la validation
  # Cas : style "oil_painting" qui n'existe pas dans l'app
  # Pourquoi : la validation inclusion empêche les valeurs arbitraires
  test "image_style inconnu est refusé par la validation" do
    # Arrange
    child = children(:leo)
    story = Story.new(child: child, status: :pending, image_style: "oil_painting")

    # Act
    story.valid?

    # Assert
    assert story.errors[:image_style].any?,
           "Un style inconnu devrait être refusé — seuls ghibli/comics/pixar/watercolor/cinematic sont autorisés"
  end

  # Vérifie que image_style peut être nil (champ optionnel)
  # Cas : histoire sans style d'illustration explicite
  # Pourquoi : allow_nil: true est déclaré dans la validation
  test "image_style nil est accepté" do
    # Arrange
    child = children(:leo)
    story = Story.new(child: child, status: :pending, image_style: nil)

    # Act
    story.valid?

    # Assert
    assert_empty story.errors[:image_style],
                 "image_style nil devrait être accepté (champ optionnel)"
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

  # ===========================================================
  # SECTION 5 — VALIDATION PREMIUM DU MODE INTERACTIF
  # ===========================================================
  # interactive_requires_premium est une garde business critique :
  # elle empêche un utilisateur gratuit de forger une requête POST
  # avec interactive=true pour contourner la checkbox désactivée.

  # Vérifie qu'un utilisateur gratuit ne peut PAS créer une histoire interactive
  # Cas : Marie (admin: false, pas d'abonnement Stripe) crée avec interactive: true
  # Pourquoi : le mode interactif est l'argument de vente principal du Premium
  test "une histoire interactive est invalide pour un utilisateur gratuit" do
    # Arrange — Léo appartient à Marie, qui n'est pas premium
    child = children(:leo)
    assert_not child.user.premium?, "Pré-condition : Marie ne doit pas être premium"

    story = child.stories.build(status: :pending, interactive: true)

    # Act
    story.valid?

    # Assert — l'erreur doit porter sur interactive
    assert story.errors[:interactive].any?,
           "Un compte gratuit ne devrait pas pouvoir créer une histoire interactive"
  end

  # Vérifie qu'un utilisateur premium PEUT créer une histoire interactive
  # Cas : admin_user (admin: true → premium? = true) crée avec interactive: true
  # Pourquoi : la validation ne doit pas bloquer les abonnés légitimes
  test "une histoire interactive est valide pour un utilisateur premium" do
    # Arrange — crée un enfant pour l'admin (la fixture admin_user n'en a pas)
    admin = users(:admin_user)
    assert admin.premium?, "Pré-condition : admin_user doit être premium (admin: true)"

    child = admin.children.create!(name: "Nina", age: 7)
    story = child.stories.build(status: :pending, interactive: true)

    # Act
    story.valid?

    # Assert — aucune erreur sur interactive
    assert_empty story.errors[:interactive],
                 "Un compte premium devrait pouvoir créer une histoire interactive"
  end

  # Vérifie qu'une histoire NON interactive reste valide pour un compte gratuit
  # Cas : Marie crée une histoire classique (interactive: false)
  # Pourquoi : la validation ne s'applique que si interactive? — pas de faux positifs
  test "une histoire non interactive est valide pour un utilisateur gratuit" do
    # Arrange
    story = children(:leo).stories.build(status: :pending, interactive: false)

    # Act + Assert
    story.valid?
    assert_empty story.errors[:interactive],
                 "Une histoire classique ne doit pas être bloquée pour un compte gratuit"
  end

  # Vérifie qu'une histoire interactive EXISTANTE reste valide après désabonnement
  # Cas : interactive_story appartient à Marie (gratuite) mais existe déjà en base
  # Pourquoi : on: :create — si un abonné se désabonne, ses histoires restent lisibles/modifiables
  test "une histoire interactive existante reste valide pour un utilisateur gratuit" do
    # Arrange — fixture déjà persistée, propriétaire non premium
    story = stories(:interactive_story)
    assert_not story.child.user.premium?, "Pré-condition : le propriétaire ne doit pas être premium"

    # Act + Assert — valid? sur un enregistrement persisté utilise le contexte :update
    # → la validation on: :create est ignorée, l'histoire reste valide
    assert story.valid?,
           "Une histoire interactive déjà créée doit rester valide après désabonnement"
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

  # ===========================================================
  # SECTION — PARTAGE PUBLIC (token signé)
  # ===========================================================

  # Vérifie qu'un token valide permet de retrouver l'histoire
  # Pourquoi : c'est le cœur du partage — le destinataire ouvre le lien signé
  test "find_by_share_token retrouve l'histoire avec un token valide" do
    # Arrange — une histoire terminée + son token de partage
    story = stories(:completed_saved)
    token = story.share_token

    # Act — on retrouve l'histoire à partir du token
    found = Story.find_by_share_token(token)

    # Assert — c'est bien la même histoire
    assert_equal story, found, "Un token valide doit retrouver son histoire"
  end

  # Vérifie qu'un token falsifié/invalide ne retourne rien (sécurité)
  # Pourquoi : un attaquant ne doit pas pouvoir forger un lien d'accès
  test "find_by_share_token retourne nil pour un token invalide" do
    # Act — on passe une chaîne qui n'est pas un token signé valide
    found = Story.find_by_share_token("token-bidon-falsifie")

    # Assert — aucun accès accordé
    assert_nil found, "Un token falsifié ne doit donner accès à aucune histoire"
  end

  # Vérifie qu'on ne partage PAS une histoire non terminée
  # Pourquoi : un lien ne doit pointer que vers une histoire lisible (status completed)
  test "find_by_share_token retourne nil pour une histoire non terminée" do
    # Arrange — une histoire encore en génération + son token
    story = stories(:pending_story)
    token = story.share_token

    # Act
    found = Story.find_by_share_token(token)

    # Assert — non terminée → pas accessible publiquement
    assert_nil found, "Une histoire non terminée ne doit pas être partageable"
  end
end
