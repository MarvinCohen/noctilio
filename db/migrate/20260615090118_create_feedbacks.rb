# Migration : crée la table des retours utilisateurs (feedbacks)
# Un retour peut être laissé par un visiteur connecté OU anonyme.
class CreateFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :feedbacks do |t|
      # Le message du retour — seul champ obligatoire (validé côté modèle)
      t.text :message
      # Email de contact — optionnel (pré-rempli si l'utilisateur est connecté)
      t.string :email
      # Catégorie du retour : bug / suggestion / autre
      t.string :category
      # URL de la page depuis laquelle le retour a été envoyé (contexte de débogage)
      t.string :page_url
      # Auteur connecté — null: true car un visiteur anonyme peut aussi laisser un avis
      # foreign_key garantit l'intégrité ; on_delete par défaut empêche de supprimer
      # un user qui a des feedbacks (on garde l'historique des retours)
      t.references :user, null: true, foreign_key: true

      t.timestamps
    end
  end
end
