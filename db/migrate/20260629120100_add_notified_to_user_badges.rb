# Migration : marquer si un badge a déjà été NOTIFIÉ à l'utilisateur.
# ============================================================
# Contexte : les badges sont attribués silencieusement pendant la génération
# (Badge.check_and_award). On veut désormais afficher une notification + confettis
# UNE SEULE FOIS, quand l'utilisateur revient sur l'app après avoir gagné un badge.
#
# Le drapeau notified distingue les badges "à célébrer" (false) des badges déjà
# fêtés (true). Le front lit les badges non notifiés, les affiche, puis appelle
# l'endpoint qui les bascule à true.
class AddNotifiedToUserBadges < ActiveRecord::Migration[8.1]
  def up
    # default: false → tout NOUVEAU badge naît "à notifier".
    # null: false → pas d'ambiguïté possible sur l'état du drapeau.
    add_column :user_badges, :notified, :boolean, default: false, null: false

    # Backfill : les badges DÉJÀ gagnés avant cette migration ne doivent pas
    # déclencher une avalanche de notifications au prochain chargement de page.
    # On les considère donc comme déjà notifiés.
    UserBadge.update_all(notified: true)
  end

  def down
    remove_column :user_badges, :notified
  end
end
