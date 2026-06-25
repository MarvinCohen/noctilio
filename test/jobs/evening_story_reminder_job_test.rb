require "test_helper"

# Tests du job EveningStoryReminderJob (rappel "histoire du soir").
# On vérifie la règle anti-spam : ne notifier QUE les comptes abonnés au push
# ET inactifs depuis 3 jours (ou jamais d'histoire).
class EveningStoryReminderJobTest < ActiveJob::TestCase
  # Crée un utilisateur de test confirmé, avec un abonnement push.
  # On part d'utilisateurs neufs pour maîtriser totalement leur historique d'histoires.
  def creer_utilisateur_abonne(email:)
    user = User.create!(
      first_name: "Test",
      last_name: "Push",
      email: email,
      password: "motdepasse123",
      password_confirmation: "motdepasse123",
      confirmed_at: Time.current
    )
    # On l'abonne au push (sinon le job l'ignore d'office)
    user.push_subscriptions.create!(
      endpoint: "https://push.example.com/#{email}",
      p256dh_key: "p256dh",
      auth_key: "auth"
    )
    user
  end

  # --- Logique de sélection (méthode privée inactive_enough?) ---

  # Un utilisateur SANS aucune histoire est considéré comme inactif → à notifier.
  test "inactive_enough? est vrai pour un utilisateur sans histoire" do
    user = creer_utilisateur_abonne(email: "sans_histoire@example.com")
    job = EveningStoryReminderJob.new
    # send permet d'appeler la méthode privée pour la tester isolément
    assert job.send(:inactive_enough?, user),
           "Un utilisateur sans histoire doit être considéré comme inactif"
  end

  # Un utilisateur avec une histoire RÉCENTE (< 3 jours) n'est PAS inactif.
  test "inactive_enough? est faux pour une histoire créée récemment" do
    user = creer_utilisateur_abonne(email: "actif@example.com")
    child = user.children.create!(name: "Mia", age: 6, gender: "girl")
    # Histoire créée aujourd'hui → l'utilisateur est actif
    child.stories.create!(status: :completed, created_at: Time.current)

    job = EveningStoryReminderJob.new
    assert_not job.send(:inactive_enough?, user),
               "Un utilisateur ayant créé une histoire aujourd'hui ne doit pas être notifié"
  end

  # Un utilisateur dont la dernière histoire date de plus de 3 jours est inactif.
  test "inactive_enough? est vrai pour une histoire vieille de plus de 3 jours" do
    user = creer_utilisateur_abonne(email: "inactif@example.com")
    child = user.children.create!(name: "Tom", age: 7, gender: "boy")
    # Histoire créée il y a 4 jours → au-delà du seuil de 3 jours
    child.stories.create!(status: :completed, created_at: 4.days.ago)

    job = EveningStoryReminderJob.new
    assert job.send(:inactive_enough?, user),
           "Une histoire vieille de 4 jours doit rendre l'utilisateur inactif"
  end

  # --- Comportement global de perform ---

  # Vérifie que perform notifie UNIQUEMENT les comptes abonnés ET inactifs.
  # On remplace PushNotificationService par un double qui enregistre les envois.
  test "perform notifie seulement les abonnés inactifs" do
    # Arrange — un inactif (sans histoire) et un actif (histoire d'aujourd'hui)
    inactif = creer_utilisateur_abonne(email: "cible@example.com")
    actif   = creer_utilisateur_abonne(email: "epargne@example.com")
    enfant_actif = actif.children.create!(name: "Lou", age: 5, gender: "girl")
    enfant_actif.stories.create!(status: :completed, created_at: Time.current)

    # On capture les endpoints réellement notifiés via un double
    notifies = []
    faux_service = Class.new do
      define_method(:initialize) { |subscription| @subscription = subscription }
      define_method(:deliver) do |**|
        notifies << @subscription.user.email
        true
      end
    end

    # Act — on substitue PushNotificationService le temps du job
    stub_method(PushNotificationService, :new, ->(sub) { faux_service.new(sub) }) do
      EveningStoryReminderJob.perform_now
    end

    # Assert — seul l'utilisateur inactif a été notifié
    assert_includes notifies, inactif.email,
                    "L'utilisateur inactif abonné doit recevoir le rappel"
    assert_not_includes notifies, actif.email,
                        "L'utilisateur actif ne doit PAS être dérangé"
  end

  # Vérifie qu'un utilisateur SANS abonnement push n'est jamais parcouru.
  test "perform ignore les utilisateurs sans abonnement push" do
    # Arrange — utilisateur inactif mais NON abonné au push
    User.create!(
      first_name: "Non",
      last_name: "Abonne",
      email: "nonabonne@example.com",
      password: "motdepasse123",
      password_confirmation: "motdepasse123",
      confirmed_at: Time.current
    )

    notifies = []
    faux_service = Class.new do
      define_method(:initialize) { |subscription| @subscription = subscription }
      define_method(:deliver) { |**| notifies << @subscription.user.email }
    end

    # Act
    stub_method(PushNotificationService, :new, ->(sub) { faux_service.new(sub) }) do
      EveningStoryReminderJob.perform_now
    end

    # Assert — aucun envoi vers ce compte non abonné
    assert_not_includes notifies, "nonabonne@example.com",
                        "Un compte sans abonnement push ne doit jamais être notifié"
  end
end
