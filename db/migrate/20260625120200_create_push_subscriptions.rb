# ============================================================
# Migration — Table push_subscriptions (abonnements aux notifications push)
# ============================================================
# Chaque ligne = un appareil/navigateur abonné aux notifications push d'un user.
# Un même utilisateur peut avoir plusieurs abonnements (téléphone + ordinateur).
# Les champs viennent de l'API PushSubscription du navigateur :
#   - endpoint : URL unique du service de push (FCM, Mozilla...) vers laquelle pousser
#   - p256dh   : clé publique de l'abonnement (chiffrement du message)
#   - auth     : secret d'authentification de l'abonnement
# ============================================================
class CreatePushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      # Propriétaire de l'abonnement — supprimé en cascade si le compte part
      t.references :user, null: false, foreign_key: true

      # URL d'envoi fournie par le navigateur (unique par appareil/navigateur)
      t.string :endpoint, null: false
      # Clés de chiffrement de l'abonnement (obligatoires pour un push chiffré)
      t.string :p256dh_key, null: false
      t.string :auth_key,   null: false

      t.timestamps
    end

    # Index unique sur l'endpoint : un même abonnement n'est stocké qu'une fois
    # (si le navigateur réémet le même endpoint, on met à jour au lieu de dupliquer).
    add_index :push_subscriptions, :endpoint, unique: true
  end
end
