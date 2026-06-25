# ============================================================
# Migration — Ajoute les modules Devise :trackable et :lockable au modèle User
# ============================================================
# :trackable  → enregistre l'activité de connexion (nb de connexions, dates, IP).
#               Utile pour les stats admin et relancer les comptes inactifs.
# :lockable   → verrouille un compte après trop d'échecs de connexion
#               (complète rack-attack côté applicatif). Stratégie retenue :
#               verrouillage après 10 échecs, déverrouillage par email.
# Migration purement ADDITIVE (nouvelles colonnes nullables / avec défaut) :
# aucun impact sur les comptes existants.
# ============================================================
class AddTrackableAndLockableToUsers < ActiveRecord::Migration[8.1]
  def change
    # ── Colonnes :trackable ──
    # Compteur de connexions réussies (démarre à 0)
    add_column :users, :sign_in_count, :integer, default: 0, null: false
    # Date/heure de la connexion en cours et de la précédente
    add_column :users, :current_sign_in_at, :datetime
    add_column :users, :last_sign_in_at,    :datetime
    # Adresses IP de la connexion en cours et de la précédente
    add_column :users, :current_sign_in_ip, :string
    add_column :users, :last_sign_in_ip,    :string

    # ── Colonnes :lockable ──
    # Nombre d'échecs de connexion consécutifs (remis à 0 après une réussite)
    add_column :users, :failed_attempts, :integer, default: 0, null: false
    # Jeton envoyé par email pour déverrouiller le compte (stratégie :email)
    add_column :users, :unlock_token, :string
    # Date/heure du verrouillage (nil = compte non verrouillé)
    add_column :users, :locked_at, :datetime

    # Index unique sur le jeton de déverrouillage — recherche rapide + unicité
    add_index :users, :unlock_token, unique: true
  end
end
