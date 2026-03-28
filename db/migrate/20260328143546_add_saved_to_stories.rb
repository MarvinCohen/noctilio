class AddSavedToStories < ActiveRecord::Migration[8.1]
  def change
    # Ajoute la colonne `saved` à la table stories
    # default: false — toute nouvelle histoire commence comme non-sauvegardée
    # null: false    — la valeur ne peut pas être NULL en base (toujours true ou false)
    add_column :stories, :saved, :boolean, default: false, null: false
  end
end
