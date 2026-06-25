# ============================================================
# Modèle PushSubscription — un abonnement aux notifications push
# ============================================================
# Représente l'autorisation donnée par un navigateur/appareil de recevoir des
# notifications push (rappel "histoire du soir"). Créé quand l'utilisateur clique
# sur "Activer les rappels" et accepte la permission du navigateur.
# ============================================================
class PushSubscription < ApplicationRecord
  # Chaque abonnement appartient à un utilisateur
  belongs_to :user

  # Tous les champs renvoyés par l'API PushSubscription du navigateur sont requis :
  # sans eux on ne peut pas envoyer de push chiffré.
  validates :endpoint,   presence: true, uniqueness: true
  validates :p256dh_key, presence: true
  validates :auth_key,   presence: true
end
