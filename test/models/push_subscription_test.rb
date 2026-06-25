require "test_helper"

# Tests du modèle PushSubscription.
# Un PushSubscription représente l'abonnement d'UN navigateur/appareil
# aux notifications push (web push). Un utilisateur peut en avoir plusieurs.
class PushSubscriptionTest < ActiveSupport::TestCase
  # Prépare un abonnement valide réutilisable dans chaque test.
  # setup est exécuté avant CHAQUE méthode de test.
  setup do
    # On rattache l'abonnement à un utilisateur des fixtures (Marie)
    @user = users(:marie)
  end

  # Construit un abonnement valide à partir de l'utilisateur de test.
  # Méthode utilitaire pour éviter de répéter les attributs partout.
  def abonnement_valide(attributs = {})
    @user.push_subscriptions.build({
      endpoint: "https://push.example.com/abc123",
      p256dh_key: "cle-publique-p256dh",
      auth_key: "cle-auth"
    }.merge(attributs))
  end

  # Vérifie qu'un abonnement avec tous les champs requis est valide.
  test "un abonnement avec endpoint, p256dh et auth est valide" do
    assert abonnement_valide.valid?,
           "Un abonnement complet devrait être valide"
  end

  # Vérifie que l'endpoint est obligatoire (c'est l'URL d'envoi du push).
  test "l'endpoint est obligatoire" do
    abonnement = abonnement_valide(endpoint: nil)
    assert_not abonnement.valid?, "Un abonnement sans endpoint est invalide"
    # On vérifie qu'une erreur est bien présente sur le champ endpoint
    # (sans tester le libellé exact, qui dépend de la locale active).
    assert abonnement.errors[:endpoint].any?,
           "Le champ endpoint devrait porter une erreur de présence"
  end

  # Vérifie que la clé p256dh est obligatoire (chiffrement du payload).
  test "la clé p256dh est obligatoire" do
    abonnement = abonnement_valide(p256dh_key: nil)
    assert_not abonnement.valid?, "Un abonnement sans clé p256dh est invalide"
  end

  # Vérifie que la clé auth est obligatoire (authentification du payload).
  test "la clé auth est obligatoire" do
    abonnement = abonnement_valide(auth_key: nil)
    assert_not abonnement.valid?, "Un abonnement sans clé auth est invalide"
  end

  # Vérifie l'unicité de l'endpoint : un même navigateur ne doit pas
  # créer deux lignes pour la même URL push.
  test "l'endpoint doit être unique" do
    # On sauvegarde un premier abonnement
    abonnement_valide.save!
    # On tente d'en créer un second avec le MÊME endpoint
    doublon = abonnement_valide
    assert_not doublon.valid?, "Deux abonnements ne peuvent pas partager le même endpoint"
  end

  # Vérifie l'association : un abonnement appartient à un utilisateur.
  test "un abonnement appartient à un utilisateur" do
    abonnement = abonnement_valide
    assert_equal @user, abonnement.user,
                 "L'abonnement doit être rattaché à son utilisateur"
  end
end
