# Test du modèle User
# Ce fichier vérifie les règles métier du modèle User :
# méthodes de comptage d'histoires, limite mensuelle, statut premium,
# et associations avec les enfants et histoires.
require "test_helper"

class UserTest < ActiveSupport::TestCase

  # ===========================================================
  # SECTION 1 — VALIDATIONS
  # ===========================================================

  # Vérifie qu'un utilisateur sans prénom est invalide
  # Cas : first_name manquant
  # Pourquoi : first_name est obligatoire pour personnaliser l'interface
  test "un utilisateur sans prénom est invalide" do
    # Arrange — on modifie l'attribut pour le rendre vide
    user = users(:marie)
    user.first_name = nil

    # Act
    user.valid?

    # Assert — on vérifie qu'il y a au moins une erreur sur first_name
    # On évite de vérifier le libellé exact du message car il dépend de la locale
    # (l'app est en français mais les messages Rails peuvent varier)
    assert user.errors[:first_name].any?, "first_name devrait être obligatoire"
  end

  # Vérifie qu'un utilisateur sans nom de famille est invalide
  # Cas : last_name manquant
  # Pourquoi : last_name est obligatoire — même raison que first_name
  test "un utilisateur sans nom de famille est invalide" do
    # Arrange
    user = users(:marie)
    user.last_name = nil

    # Act
    user.valid?

    # Assert
    # Même approche : on vérifie la présence d'une erreur, pas le libellé traduit
    assert user.errors[:last_name].any?, "last_name devrait être obligatoire"
  end

  # Vérifie qu'un prénom trop long est rejeté
  # Cas : first_name > 50 caractères
  # Pourquoi : contrainte de longueur déclarée dans le modèle (maximum: 50)
  test "un prénom de plus de 50 caractères est invalide" do
    # Arrange
    user = users(:marie)
    user.first_name = "A" * 51   # 51 caractères — dépasse la limite

    # Act
    user.valid?

    # Assert
    assert user.errors[:first_name].any?,
           "Un prénom de 51 caractères devrait être rejeté"
  end

  # ===========================================================
  # SECTION 2 — MÉTHODE stories_this_week
  # ===========================================================

  # Vérifie que stories_this_week compte correctement les histoires de la semaine en cours
  # Cas : utilisateur avec plusieurs histoires cette semaine et 1 histoire ancienne
  # Pourquoi : cette méthode pilote la limite hebdomadaire des utilisateurs gratuits
  test "stories_this_week compte les histoires de la semaine courante" do
    # Arrange — Marie a completed_saved + completed_not_saved + pending + failed + interactive
    # créées cette semaine (created_at: Time.current dans les fixtures), et old_story il y a 2 mois
    user = users(:marie)

    # Act
    count = user.stories_this_week

    # Assert — old_story (il y a 2 mois) ne doit PAS être comptée
    # Les histoires de la semaine courante : completed_saved, completed_not_saved, pending_story,
    # failed_story, interactive_story → 5 histoires cette semaine
    assert_equal 5, count,
                 "stories_this_week devrait retourner 5 (old_story exclue car trop ancienne)"
  end

  # Vérifie que stories_this_week retourne 0 pour un utilisateur sans histoire
  # Cas : admin_user n'a pas d'enfant ni d'histoire dans les fixtures
  # Pourquoi : cas de base pour un nouveau compte
  test "stories_this_week retourne 0 pour un utilisateur sans histoire" do
    # Arrange — admin_user n'a pas d'enfant dans les fixtures
    user = users(:admin_user)

    # Act
    count = user.stories_this_week

    # Assert
    assert_equal 0, count,
                 "Un utilisateur sans histoire devrait avoir stories_this_week == 0"
  end

  # ===========================================================
  # SECTION 3 — MÉTHODE can_create_story?
  # ===========================================================

  # Vérifie que can_create_story? retourne true si l'utilisateur a moins de 3 histoires cette semaine
  # Cas : utilisateur avec 1 histoire cette semaine (Paul a paul_story)
  # Pourquoi : règle métier fondamentale — les gratuits ont 3 histoires/semaine
  test "can_create_story? retourne true si moins de 3 histoires cette semaine" do
    # Arrange — Paul a 1 seule histoire cette semaine donc 1 < 3
    user = users(:paul)
    assert_not user.premium?, "Pré-condition : Paul ne doit pas être premium"

    # Act + Assert
    assert user.can_create_story?,
           "Paul a 1 histoire cette semaine, il devrait pouvoir en créer d'autres (limite: 3)"
  end

  # Vérifie que can_create_story? retourne false quand la limite de 3 est atteinte
  # Cas : utilisateur avec exactement 3 histoires cette semaine
  # Pourquoi : au-delà de 3, l'utilisateur gratuit est bloqué jusqu'au lundi suivant
  test "can_create_story? retourne false si 3 histoires ou plus cette semaine" do
    # Arrange — Paul a déjà 1 histoire (paul_story), on en crée 2 de plus
    user = users(:paul)
    child = children(:theo)

    # Crée 2 histoires supplémentaires pour atteindre la limite
    2.times do
      child.stories.create!(status: :pending)
    end

    # Vérifie la pré-condition : Paul doit bien avoir 3 histoires maintenant
    assert_equal 3, user.stories_this_week,
                 "Pré-condition : Paul doit avoir exactement 3 histoires cette semaine"

    # Assert — la limite est atteinte, plus de création possible
    assert_not user.can_create_story?,
               "can_create_story? devrait retourner false quand la limite de 3 est atteinte"
  end

  # Vérifie que can_create_story? retourne toujours true pour un admin (premium)
  # Cas : admin_user avec admin == true
  # Pourquoi : les admins ont un accès illimité via premium? qui retourne true
  test "can_create_story? retourne true pour un admin même au-delà de la limite" do
    # Arrange
    user = users(:admin_user)

    # Assert — admin → premium → can_create_story? ignore le compteur
    assert user.can_create_story?,
           "Un admin devrait toujours pouvoir créer des histoires (accès illimité)"
  end

  # ===========================================================
  # SECTION 3bis — OFFRE DÉCOUVERTE (1re histoire en accès complet)
  # ===========================================================

  # Vérifie que welcome_story? reconnaît la 1re histoire du compte
  # Cas : Paul (gratuit) a une seule histoire (paul_story) → c'est sa 1re
  # Pourquoi : la 1re histoire débloque l'expérience complète (image + audio + interactif)
  test "welcome_story? retourne true pour la 1re histoire du compte" do
    # Arrange — Paul a une seule histoire dans les fixtures
    user = users(:paul)

    # Act + Assert — paul_story est la plus petite id → c'est la 1re histoire
    assert user.welcome_story?(stories(:paul_story)),
           "paul_story devrait être reconnue comme la 1re histoire de Paul"
  end

  # Vérifie que welcome_story? retourne false pour une histoire qui n'est PAS la 1re
  # Cas : on crée une 2e histoire pour Paul → elle a une id plus grande
  # Pourquoi : seule la toute 1re histoire est offerte, pas les suivantes
  test "welcome_story? retourne false pour une histoire qui n'est pas la 1re" do
    # Arrange — Paul a déjà paul_story ; on crée une 2e histoire (id plus grande)
    user = users(:paul)
    seconde_histoire = children(:theo).stories.create!(status: :pending)

    # Act + Assert — la 2e histoire n'est pas la plus petite id → pas offerte
    assert_not user.welcome_story?(seconde_histoire),
               "Une 2e histoire ne devrait PAS être reconnue comme la 1re"
  end

  # Vérifie que welcome_story? retourne false pour une histoire non sauvegardée (id nil)
  # Cas : Story.new sans save → id == nil
  # Pourquoi : on ne peut pas comparer une histoire inexistante en base
  test "welcome_story? retourne false si l'histoire n'a pas d'id" do
    # Arrange — histoire en mémoire, jamais sauvegardée
    user = users(:paul)
    histoire_non_sauvee = Story.new

    # Act + Assert — id nil → la méthode renvoie false sans planter
    assert_not user.welcome_story?(histoire_non_sauvee),
               "Une histoire sans id ne devrait jamais être la 1re histoire"
  end

  # Vérifie que full_experience_for? est true pour la 1re histoire d'un gratuit
  # Cas : Paul (gratuit) + sa 1re histoire (paul_story)
  # Pourquoi : règle métier de l'offre découverte — la 1re histoire est en accès complet
  test "full_experience_for? retourne true pour la 1re histoire d'un gratuit" do
    # Arrange
    user = users(:paul)
    assert_not user.premium?, "Pré-condition : Paul ne doit pas être premium"

    # Act + Assert — gratuit mais 1re histoire → expérience complète
    assert user.full_experience_for?(stories(:paul_story)),
           "La 1re histoire d'un gratuit devrait avoir l'expérience complète"
  end

  # Vérifie que full_experience_for? est false pour la 2e histoire d'un gratuit
  # Cas : Paul (gratuit) + une 2e histoire
  # Pourquoi : dès la 2e histoire, le gratuit repasse en texte seul
  test "full_experience_for? retourne false pour la 2e histoire d'un gratuit" do
    # Arrange — on crée une 2e histoire pour Paul
    user = users(:paul)
    seconde_histoire = children(:theo).stories.create!(status: :pending)

    # Act + Assert — gratuit et pas la 1re → texte seul
    assert_not user.full_experience_for?(seconde_histoire),
               "La 2e histoire d'un gratuit ne devrait PAS avoir l'expérience complète"
  end

  # Vérifie que full_experience_for? est toujours true pour un premium (admin)
  # Cas : admin_user (premium) + une histoire qui n'est pas la sienne
  # Pourquoi : un premium a l'expérience complète sur TOUTES ses histoires, peu importe l'ordre
  test "full_experience_for? retourne true pour un premium quelle que soit l'histoire" do
    # Arrange — admin est premium ; on passe une histoire quelconque
    user = users(:admin_user)
    assert user.premium?, "Pré-condition : admin_user doit être premium"

    # Act + Assert — premium → expérience complète sans vérifier si c'est la 1re
    assert user.full_experience_for?(stories(:completed_saved)),
           "Un premium devrait toujours avoir l'expérience complète"
  end

  # Vérifie que first_story_pending? est true quand l'utilisateur n'a aucune histoire
  # Cas : admin_user n'a pas d'enfant ni d'histoire dans les fixtures
  # Pourquoi : pilote l'affichage de la bannière d'offre et du toggle interactif dans le formulaire
  test "first_story_pending? retourne true sans aucune histoire" do
    # Arrange
    user = users(:admin_user)

    # Act + Assert — aucune histoire → la prochaine sera la 1re
    assert user.first_story_pending?,
           "first_story_pending? devrait être true pour un compte sans histoire"
  end

  # Vérifie que first_story_pending? est false dès qu'une histoire existe
  # Cas : Marie a déjà plusieurs histoires
  # Pourquoi : l'offre découverte ne doit plus s'afficher une fois la 1re histoire créée
  test "first_story_pending? retourne false si l'utilisateur a déjà une histoire" do
    # Arrange
    user = users(:marie)

    # Act + Assert — Marie a des histoires → l'offre n'est plus disponible
    assert_not user.first_story_pending?,
               "first_story_pending? devrait être false dès qu'une histoire existe"
  end

  # ===========================================================
  # SECTION 4 — MÉTHODE premium?
  # ===========================================================

  # Vérifie que premium? retourne false pour un utilisateur standard
  # Cas : utilisateur normal non-admin, Stripe pas encore configuré
  # Pourquoi : Stripe n'est pas encore intégré — tous les non-admins sont gratuits
  test "premium? retourne false pour un utilisateur non-admin" do
    # Arrange
    user = users(:marie)
    assert_not user.admin?, "Pré-condition : Marie ne doit pas être admin"

    # Act + Assert
    assert_not user.premium?,
               "premium? devrait retourner false (Stripe pas encore configuré)"
  end

  # Vérifie que premium? retourne true pour un admin
  # Cas : utilisateur avec admin == true
  # Pourquoi : les admins ont accès premium pour tester toutes les fonctionnalités en prod
  test "premium? retourne true pour un admin" do
    # Arrange
    user = users(:admin_user)
    assert user.admin?, "Pré-condition : admin_user doit avoir admin == true"

    # Act + Assert
    assert user.premium?,
           "premium? devrait retourner true pour un admin"
  end

  # ===========================================================
  # SECTION 5 — ASSOCIATIONS
  # ===========================================================

  # Vérifie que l'association has_many :children fonctionne
  # Cas : Marie a deux enfants (Léo et Emma dans les fixtures)
  # Pourquoi : les enfants sont le coeur du produit — cette association doit être fiable
  test "un utilisateur peut avoir plusieurs enfants" do
    # Arrange
    user = users(:marie)

    # Act — charge les enfants via l'association ActiveRecord
    kids = user.children

    # Assert — Marie a Léo et Emma dans les fixtures
    assert_equal 2, kids.count,
                 "Marie devrait avoir 2 enfants (Léo et Emma)"
    assert_includes kids.map(&:name), "Léo"
    assert_includes kids.map(&:name), "Emma"
  end

  # Vérifie que l'association has_many :stories through :children fonctionne
  # Cas : Marie a des histoires via ses enfants Léo et Emma
  # Pourquoi : User#stories traverse children — si cassée, le comptage de limites et badges plante
  test "un utilisateur peut accéder à ses histoires via ses enfants" do
    # Arrange
    user = users(:marie)

    # Act
    user_stories = user.stories

    # Assert — Marie doit avoir des histoires via Léo
    assert user_stories.any?,
           "Marie devrait avoir des histoires accessibles via l'association through :children"
  end

  # Vérifie que la suppression d'un utilisateur supprime ses enfants en cascade
  # Cas : dependent: :destroy sur has_many :children
  # Pourquoi : pas d'orphelins en base quand un compte est supprimé
  test "supprimer un utilisateur supprime ses enfants en cascade" do
    # Arrange — crée un utilisateur temporaire avec un enfant
    temp_user = User.create!(
      email: "temp_cascade@example.com",
      password: "password123",
      first_name: "Temp",
      last_name: "User"
    )
    child = temp_user.children.create!(name: "Mini", age: 5)
    child_id = child.id

    # Act — supprime l'utilisateur
    temp_user.destroy

    # Assert — l'enfant doit avoir été supprimé automatiquement
    assert_nil Child.find_by(id: child_id),
               "L'enfant devrait être supprimé quand l'utilisateur est supprimé (dependent: :destroy)"
  end

  # ===========================================================
  # SECTION 6 — MÉTHODE full_name
  # ===========================================================

  # Vérifie que full_name concatène prénom et nom avec un espace
  # Cas : utilisateur avec first_name et last_name bien renseignés
  # Pourquoi : affiché dans les emails Devise et l'interface utilisateur
  test "full_name retourne le nom complet avec un espace" do
    # Arrange
    user = users(:marie)

    # Assert
    assert_equal "Marie Dupont", user.full_name
  end

  # ===========================================================
  # SECTION 7 — MÉTHODE xp_points
  # ===========================================================

  # Vérifie que xp_points calcule bien 100 XP/histoire terminée + 50 XP/badge
  # Cas : Marie a 4 histoires completed et 1 badge dans les fixtures
  # Pourquoi : les XP sont affichés dans la page trophées — calcul doit être exact
  test "xp_points calcule correctement 100 XP par histoire et 50 XP par badge" do
    # Arrange — Marie a dans les fixtures :
    #   Histoires completed : completed_saved + completed_not_saved + interactive_story + old_story = 4 → 400 XP
    #   Badges             : marie_first_story → 50 XP
    #   Total attendu      : 450 XP
    user = users(:marie)

    # Act
    xp = user.xp_points

    # Assert — 4 × 100 + 1 × 50 = 450
    assert_equal 450, xp,
                 "xp_points devrait être 450 (4 histoires completed × 100 XP + 1 badge × 50 XP)"
  end

  # Vérifie que xp_points retourne 0 pour un utilisateur sans histoire ni badge
  # Cas : nouveau compte sans activité
  # Pourquoi : valeur plancher, on ne doit pas avoir de XP négatifs ou nil
  test "xp_points retourne 0 pour un utilisateur sans histoire ni badge" do
    # Arrange — admin_user n'a ni enfant, ni histoire, ni badge dans les fixtures
    user = users(:admin_user)

    # Act
    xp = user.xp_points

    # Assert
    assert_equal 0, xp,
                 "Un utilisateur sans activité devrait avoir 0 XP"
  end
end
