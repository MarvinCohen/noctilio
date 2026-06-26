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

  # === Palier d'abonnement (subscription_tier) ===

  # Vérifie qu'un admin est toujours considéré comme Premium
  # Cas : admin_user (admin? == true)
  # Pourquoi : subscription_tier court-circuite et renvoie :premium pour les admins
  test "subscription_tier retourne :premium pour un admin" do
    # Act + Assert — l'admin n'a pas besoin d'abonnement Stripe pour être Premium
    assert_equal :premium, users(:admin_user).subscription_tier
  end

  # Vérifie qu'un utilisateur sans abonnement actif est :free
  # Cas : Paul (pas admin, pas d'abonnement Pay)
  # Pourquoi : aucun payment_processor abonné → palier gratuit
  test "subscription_tier retourne :free sans abonnement actif" do
    # Act + Assert — Paul n'a aucun abonnement → gratuit
    assert_equal :free, users(:paul).subscription_tier
  end

  # Vérifie que subscription_tier renvoie :essentiel quand le plan == l'ID Essentiel
  # Cas : on simule un payment_processor abonné dont le plan == STRIPE_ESSENTIEL_PRICE_ID
  # Pourquoi : c'est exactement ce qui distingue Essentiel de Premium
  test "subscription_tier retourne :essentiel quand le plan correspond à l'ID Essentiel" do
    # Arrange — un prix factice et le double d'abonnement qui le porte
    user = users(:paul)
    prix_essentiel = "price_essentiel_test"
    # Double minimal d'un abonnement Pay : seul processor_plan est lu
    abonnement = Object.new
    abonnement.define_singleton_method(:processor_plan) { prix_essentiel }
    # Double minimal d'un payment_processor abonné
    faux_processor = Object.new
    faux_processor.define_singleton_method(:subscribed?) { true }
    faux_processor.define_singleton_method(:subscription) { abonnement }

    # On force l'ENV lue par subscription_tier le temps du test, puis on restaure
    ancien_id = ENV["STRIPE_ESSENTIEL_PRICE_ID"]
    begin
      ENV["STRIPE_ESSENTIEL_PRICE_ID"] = prix_essentiel
      # On remplace payment_processor par notre double
      stub_method(user, :payment_processor, -> { faux_processor }) do
        # Act + Assert — plan == ID Essentiel → palier Essentiel
        assert_equal :essentiel, user.subscription_tier
      end
    ensure
      ENV["STRIPE_ESSENTIEL_PRICE_ID"] = ancien_id
    end
  end

  # Vérifie que tout abonnement payant inconnu retombe sur :premium (jamais rétrograder un payeur)
  # Cas : payment_processor abonné dont le plan != ID Essentiel
  # Pourquoi : règle de sécurité — un client qui paie ne doit jamais perdre l'accès Premium
  test "subscription_tier retourne :premium pour un plan payant non Essentiel" do
    # Arrange — abonnement avec un plan qui ne correspond pas à l'Essentiel
    user = users(:paul)
    abonnement = Object.new
    abonnement.define_singleton_method(:processor_plan) { "price_inconnu" }
    faux_processor = Object.new
    faux_processor.define_singleton_method(:subscribed?) { true }
    faux_processor.define_singleton_method(:subscription) { abonnement }

    ancien_id = ENV["STRIPE_ESSENTIEL_PRICE_ID"]
    begin
      ENV["STRIPE_ESSENTIEL_PRICE_ID"] = "price_essentiel_test"
      stub_method(user, :payment_processor, -> { faux_processor }) do
        # Act + Assert — plan inconnu → on suppose Premium
        assert_equal :premium, user.subscription_tier
      end
    ensure
      ENV["STRIPE_ESSENTIEL_PRICE_ID"] = ancien_id
    end
  end

  # Vérifie les prédicats dérivés du palier Essentiel
  # Cas : on force subscription_tier à :essentiel
  # Pourquoi : essentiel? et unlimited_stories? vrais, mais premium? faux
  test "predicats du palier Essentiel : essentiel? et unlimited_stories? vrais, premium? faux" do
    # Arrange — on stub directement le palier pour isoler les prédicats
    user = users(:paul)
    stub_method(user, :subscription_tier, -> { :essentiel }) do
      # Act + Assert
      assert user.essentiel?, "Essentiel doit répondre essentiel? == true"
      assert_not user.premium?, "Essentiel ne doit PAS être premium?"
      assert user.unlimited_stories?, "Essentiel doit avoir les histoires illimitées"
    end
  end

  # === Verrous de fonctionnalités par palier (illustrations_for? / audio_for?) ===

  # Vérifie qu'un Essentiel a les illustrations mais PAS l'audio (hors offre découverte)
  # Cas : admin_user sans histoire (welcome_story? toujours false) forcé à :essentiel
  # Pourquoi : l'audio est réservé au Premium, l'illustration est incluse dès l'Essentiel
  test "Essentiel : illustrations oui, audio non, pour une histoire hors offre decouverte" do
    # Arrange — admin n'a aucune histoire → welcome_story? renverra false
    user = users(:admin_user)
    histoire = stories(:completed_saved)
    stub_method(user, :subscription_tier, -> { :essentiel }) do
      # Act + Assert
      assert user.illustrations_for?(histoire), "Essentiel doit avoir les illustrations"
      assert_not user.audio_for?(histoire), "Essentiel ne doit PAS avoir l'audio"
    end
  end

  # Vérifie qu'un Premium a illustrations ET audio sur n'importe quelle histoire
  # Cas : admin_user (Premium) + une histoire quelconque
  # Pourquoi : le Premium débloque tout, sans condition d'ordre
  test "Premium : illustrations et audio pour toute histoire" do
    # Arrange — admin est Premium via subscription_tier
    user = users(:admin_user)
    histoire = stories(:completed_saved)

    # Act + Assert
    assert user.illustrations_for?(histoire), "Premium doit avoir les illustrations"
    assert user.audio_for?(histoire), "Premium doit avoir l'audio"
  end

  # Vérifie l'offre découverte : la 1re histoire d'un gratuit a tout (image + audio)
  # Cas : Paul (gratuit) + sa 1re histoire (paul_story)
  # Pourquoi : la 1re histoire est en accès complet pour donner envie de s'abonner
  test "Gratuit : illustrations et audio pour la 1re histoire (offre decouverte)" do
    # Arrange
    user = users(:paul)
    assert_not user.unlimited_stories?, "Pré-condition : Paul est gratuit"

    # Act + Assert — 1re histoire → expérience complète malgré le palier gratuit
    assert user.illustrations_for?(stories(:paul_story)),
           "La 1re histoire d'un gratuit doit avoir les illustrations"
    assert user.audio_for?(stories(:paul_story)),
           "La 1re histoire d'un gratuit doit avoir l'audio"
  end

  # Vérifie que dès la 2e histoire, le gratuit repasse en texte seul
  # Cas : Paul (gratuit) + une 2e histoire créée à la volée
  # Pourquoi : l'offre découverte ne couvre que la toute première histoire
  test "Gratuit : ni illustrations ni audio des la 2e histoire" do
    # Arrange — on crée une 2e histoire pour Paul
    user = users(:paul)
    seconde_histoire = children(:theo).stories.create!(status: :pending)

    # Act + Assert — gratuit et pas la 1re → texte seul
    assert_not user.illustrations_for?(seconde_histoire),
               "La 2e histoire d'un gratuit ne doit PAS avoir d'illustrations"
    assert_not user.audio_for?(seconde_histoire),
               "La 2e histoire d'un gratuit ne doit PAS avoir d'audio"
  end

  # Vérifie que can_create_story? est vrai pour tout palier à histoires illimitées
  # Cas : on force subscription_tier à :essentiel
  # Pourquoi : Essentiel comme Premium doivent contourner le quota hebdomadaire
  test "can_create_story? est vrai pour un palier illimite" do
    # Arrange
    user = users(:paul)
    stub_method(user, :subscription_tier, -> { :essentiel }) do
      # Act + Assert — pas de limite hebdo pour un palier illimité
      assert user.can_create_story?,
             "Un palier illimité doit pouvoir créer une histoire sans quota"
    end
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

  # ===========================================================
  # SECTION 8 — MÉTHODE gdpr_export (export RGPD)
  # ===========================================================

  # Vérifie que l'export contient les 3 blocs attendus (compte, enfants, gamification)
  # Cas : Marie a un compte, des enfants et un badge dans les fixtures
  # Pourquoi : structure de base de l'export — le JSON téléchargé doit être complet
  test "gdpr_export retourne les blocs compte, enfants et gamification" do
    # Arrange
    user = users(:marie)

    # Act
    export = user.gdpr_export

    # Assert — les 3 clés racines doivent être présentes
    assert export.key?(:compte),      "L'export devrait contenir un bloc :compte"
    assert export.key?(:enfants),     "L'export devrait contenir un bloc :enfants"
    assert export.key?(:gamification), "L'export devrait contenir un bloc :gamification"
  end

  # Vérifie que le bloc compte contient l'email mais JAMAIS le mot de passe chiffré
  # Cas : Marie exporte ses données
  # Pourquoi : sécurité — on ne doit jamais exposer encrypted_password dans l'export
  test "gdpr_export inclut l'email mais exclut le mot de passe chiffré" do
    # Arrange
    user = users(:marie)

    # Act
    compte = user.gdpr_export[:compte]

    # Assert 1 — l'email est bien présent
    assert_equal "marie@example.com", compte[:email],
                 "L'export devrait contenir l'email de l'utilisateur"

    # Assert 2 — aucune clé ne doit ressembler à un mot de passe (sécurité)
    assert_not compte.key?(:encrypted_password),
               "L'export ne doit JAMAIS contenir le mot de passe chiffré"
    assert_not compte.key?(:password),
               "L'export ne doit JAMAIS contenir de mot de passe"
  end

  # Vérifie que l'export ne contient QUE les enfants de l'utilisateur (scoping)
  # Cas : Marie a Léo et Emma ; Théo appartient à Paul
  # Pourquoi : sécurité — un utilisateur ne doit jamais exporter les données d'un autre
  test "gdpr_export ne contient que les enfants de l'utilisateur" do
    # Arrange
    user = users(:marie)

    # Act — on récupère les noms des enfants exportés
    noms_enfants = user.gdpr_export[:enfants].map { |enfant| enfant[:nom] }

    # Assert — Léo et Emma présents, Théo (enfant de Paul) absent
    assert_includes noms_enfants, "Léo"
    assert_includes noms_enfants, "Emma"
    assert_not_includes noms_enfants, "Théo",
                        "L'export de Marie ne doit pas contenir l'enfant d'un autre compte"
  end

  # Vérifie que les histoires sont imbriquées sous chaque enfant
  # Cas : Léo (enfant de Marie) a plusieurs histoires
  # Pourquoi : le contenu des histoires fait partie des données personnelles à exporter
  test "gdpr_export imbrique les histoires sous chaque enfant" do
    # Arrange — on isole l'enfant Léo dans l'export
    user = users(:marie)
    leo_export = user.gdpr_export[:enfants].find { |enfant| enfant[:nom] == "Léo" }

    # Act + Assert — Léo a des histoires dans les fixtures
    assert leo_export[:histoires].any?,
           "Les histoires de Léo devraient être imbriquées dans son export"
  end

  # Vérifie que le bloc gamification contient les badges avec leur clé
  # Cas : Marie a le badge first_story (condition_key: "first_story")
  # Pourquoi : XP et badges font partie des données à exporter
  test "gdpr_export inclut les badges obtenus avec leur clé" do
    # Arrange
    user = users(:marie)

    # Act — on récupère les clés des badges exportés
    cles_badges = user.gdpr_export[:gamification][:badges].map { |badge| badge[:cle] }

    # Assert — le badge first_story de Marie doit apparaître
    assert_includes cles_badges, "first_story",
                    "L'export devrait contenir le badge first_story obtenu par Marie"
  end

  # ============================================================
  # SECTION 9 — Trackable / Lockable / Confirmable + OmniAuth
  # Couvre les modules Devise ajoutés (chantiers D, B, A) et la
  # logique de confirmation dans from_omniauth.
  # ============================================================

  # --- Confirmable : période de grâce de 7 jours (config/initializers/devise.rb) ---

  # Vérifie qu'un nouveau compte email est NON confirmé mais reste actif
  # pendant la période de grâce (allow_unconfirmed_access_for = 7.days).
  # Pourquoi : on ne veut pas bloquer l'utilisateur dès l'inscription,
  # il a 7 jours pour cliquer sur le lien de confirmation.
  test "un nouveau compte email n'est pas confirmé mais reste actif (grâce 7 jours)" do
    # Arrange — création d'un compte email/mot de passe classique
    user = User.create!(
      first_name: "Nina",
      last_name: "Test",
      email: "nina@example.com",
      password: "motdepasse123",
      password_confirmation: "motdepasse123"
    )

    # Assert — l'email n'est pas encore confirmé...
    assert_not user.confirmed?,
               "Un compte email fraîchement créé ne doit pas être confirmé automatiquement"
    # ...mais il peut quand même se connecter (encore dans les 7 jours de grâce)
    assert user.active_for_authentication?,
           "Pendant la période de grâce de 7 jours, le compte non confirmé reste actif"
  end

  # Vérifie qu'au-delà de la période de grâce, un compte non confirmé est bloqué.
  # Pourquoi : passé 7 jours sans confirmation, Devise refuse la connexion.
  test "un compte non confirmé est bloqué après la période de grâce" do
    # Arrange — compte créé il y a plus de 7 jours, jamais confirmé
    user = User.create!(
      first_name: "Vieux",
      last_name: "Compte",
      email: "vieux@example.com",
      password: "motdepasse123",
      password_confirmation: "motdepasse123"
    )
    # On simule un email de confirmation envoyé il y a 8 jours (hors grâce)
    user.update_columns(confirmation_sent_at: 8.days.ago)

    # Assert — la connexion n'est plus permise
    assert_not user.active_for_authentication?,
               "Passé les 7 jours de grâce, un compte non confirmé doit être bloqué"
  end

  # --- Lockable : verrouillage après 10 échecs (maximum_attempts = 10) ---

  # Vérifie que le compte se verrouille après 10 tentatives de connexion ratées.
  # Pourquoi : protection contre les attaques par force brute (chantier D).
  test "le compte se verrouille après 10 tentatives de connexion échouées" do
    # Arrange
    user = users(:marie)

    # Act — on simule 10 authentifications ratées (le bloc renvoie false = échec)
    10.times { user.valid_for_authentication? { false } }

    # Assert — le compte est désormais verrouillé
    assert user.reload.access_locked?,
           "Après 10 échecs, le compte doit être verrouillé (lockable)"
  end

  # Vérifie qu'avant d'atteindre le seuil, le compte reste déverrouillé.
  # Pourquoi : on ne verrouille qu'au 10e échec, pas avant.
  test "le compte reste déverrouillé en dessous de 10 tentatives échouées" do
    # Arrange
    user = users(:marie)

    # Act — 9 échecs seulement
    9.times { user.valid_for_authentication? { false } }

    # Assert — toujours accessible
    assert_not user.reload.access_locked?,
               "En dessous de 10 échecs, le compte ne doit pas être verrouillé"
  end

  # --- OmniAuth : confirmation automatique via Google ---

  # Vérifie qu'un nouvel utilisateur créé via Google est confirmé d'office.
  # Pourquoi : Google a déjà vérifié l'email, inutile de redemander une confirmation
  # (skip_confirmation! dans from_omniauth).
  test "from_omniauth crée un utilisateur Google déjà confirmé" do
    # Arrange — on simule le hash renvoyé par OmniAuth/Google
    auth = mock_google_auth(uid: "google-123", email: "google@example.com")

    # Act
    user = User.from_omniauth(auth)

    # Assert — compte créé ET confirmé sans email de confirmation
    assert user.persisted?, "from_omniauth doit créer et sauvegarder l'utilisateur"
    assert user.confirmed?, "Un compte créé via Google doit être confirmé d'office"
  end

  # Vérifie qu'un compte email existant NON confirmé est confirmé quand
  # l'utilisateur se connecte ensuite via Google avec le même email.
  # Pourquoi : Google prouve la possession de l'email, on le confirme (line 307).
  test "from_omniauth confirme un compte email existant non confirmé" do
    # Arrange — compte email non confirmé
    user = User.create!(
      first_name: "Lien",
      last_name: "Google",
      email: "lien@example.com",
      password: "motdepasse123",
      password_confirmation: "motdepasse123"
    )
    assert_not user.confirmed?, "Préalable : le compte ne doit pas être confirmé"

    # Act — connexion via Google avec le MÊME email
    auth = mock_google_auth(uid: "google-456", email: "lien@example.com")
    returned = User.from_omniauth(auth)

    # Assert — c'est bien le même compte, désormais confirmé et lié à Google
    assert_equal user.id, returned.id, "from_omniauth doit retrouver le compte par email"
    assert returned.confirmed?, "Le compte doit être confirmé après connexion Google"
    assert_equal "google_oauth2", returned.provider, "Le compte doit être lié à Google"
  end

  private

  # Construit un faux objet `auth` OmniAuth (style Google) pour les tests.
  # OpenStruct permet d'accéder aux attributs en notation pointée (auth.info.email).
  def mock_google_auth(uid:, email:, first_name: "Prénom", last_name: "Nom")
    require "ostruct"
    OpenStruct.new(
      provider: "google_oauth2",
      uid: uid,
      info: OpenStruct.new(email: email, first_name: first_name, last_name: last_name)
    )
  end
end
