# ============================================================
# Migration de SCHÉMA : pose des contraintes NOT NULL au niveau BASE
# sur des colonnes déjà validées presence côté modèle.
#
# Pourquoi ?
#   Les validations Ruby (presence: true) protègent le flux applicatif
#   normal, mais PAS une insertion directe (SQL brut, console, import,
#   ou un futur bug qui contournerait le modèle). La contrainte NOT NULL
#   en base est la dernière ligne de défense : la donnée corrompue est
#   refusée par PostgreSQL lui-même.
#
# Colonnes concernées :
#   feedbacks.message        — le coeur du retour, jamais vide
#   feedbacks.category       — toujours une des CATEGORIES autorisées
#   waitlist_entries.email   — un inscrit sans email est inutile
#
# Sécurité déploiement (Railway) :
#   change_column_null(.., false) ÉCHOUE si une ligne nulle existe déjà.
#   Comme les validations presence existent depuis toujours, on n'attend
#   aucune ligne nulle. Mais par prudence, on NETTOIE défensivement avant
#   de poser la contrainte, pour qu'un déploiement ne casse pas sur une
#   éventuelle donnée historique.
# ============================================================
class AddNotNullConstraintsToFeedbacksAndWaitlist < ActiveRecord::Migration[8.1]
  # Pose les contraintes NOT NULL
  def up
    # ── Nettoyage défensif (en pratique 0 ligne touchée) ──

    # Un retour sans message n'a aucune valeur → on le supprime.
    Feedback.where(message: nil).delete_all

    # Un retour sans catégorie mais AVEC un message : on préserve le message
    # en lui attribuant la catégorie neutre "autre" (valeur valide du modèle),
    # plutôt que de le détruire.
    Feedback.where(category: nil).update_all(category: "autre")

    # Un inscrit liste d'attente sans email est inutilisable → on le supprime.
    WaitlistEntry.where(email: nil).delete_all

    # ── Pose des contraintes NOT NULL côté PostgreSQL ──
    change_column_null :feedbacks, :message, false
    change_column_null :feedbacks, :category, false
    change_column_null :waitlist_entries, :email, false
  end

  # Réversibilité : on repose les colonnes en nullable.
  # ⚠️ Les lignes supprimées dans up() ne sont PAS restaurées (donnée perdue),
  # mais comme ce sont des lignes vides/corrompues, c'est sans conséquence.
  def down
    change_column_null :feedbacks, :message, true
    change_column_null :feedbacks, :category, true
    change_column_null :waitlist_entries, :email, true
  end
end
