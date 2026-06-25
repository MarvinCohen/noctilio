# ============================================================
# Migration — Ajoute le module Devise :confirmable au modèle User
# ============================================================
# :confirmable → l'utilisateur doit confirmer son adresse email via un lien
#                envoyé par mail. Fiabilise la base (moins de faux comptes,
#                moins de bounces) et sécurise les emails transactionnels.
#
# IMPORTANT — Backfill : les comptes DÉJÀ existants n'ont jamais reçu d'email
# de confirmation. Si on les laissait "non confirmés", ils seraient bloqués au
# bout de la période de grâce (7 jours). On les marque donc tous comme confirmés
# à la date de cette migration → aucun utilisateur existant n'est impacté.
# Seuls les NOUVEAUX comptes devront confirmer leur email.
# ============================================================
class AddConfirmableToUsers < ActiveRecord::Migration[8.1]
  def up
    # Jeton unique envoyé dans le lien de confirmation par email
    add_column :users, :confirmation_token, :string
    # Date/heure de confirmation (nil = compte pas encore confirmé)
    add_column :users, :confirmed_at, :datetime
    # Date/heure d'envoi du dernier email de confirmation (sert au calcul de la grâce)
    add_column :users, :confirmation_sent_at, :datetime
    # Email "en attente" lors d'un changement d'adresse (reconfirmable = true) :
    # la nouvelle adresse n'écrase l'ancienne qu'une fois confirmée.
    add_column :users, :unconfirmed_email, :string

    # Index unique sur le jeton — recherche rapide lors de la confirmation + unicité
    add_index :users, :confirmation_token, unique: true

    # ── Backfill : on confirme tous les comptes déjà créés ──
    # update_all écrit directement en SQL (pas de callbacks) → rapide et sûr.
    User.reset_column_information
    User.update_all(confirmed_at: Time.current)
  end

  def down
    remove_index  :users, :confirmation_token
    remove_column :users, :confirmation_token
    remove_column :users, :confirmed_at
    remove_column :users, :confirmation_sent_at
    remove_column :users, :unconfirmed_email
  end
end
