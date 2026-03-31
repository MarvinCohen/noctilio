class AddExtraChildIdsToStories < ActiveRecord::Migration[8.1]
  def change
    # Ajoute un tableau d'IDs d'enfants supplémentaires
    # PostgreSQL supporte les colonnes de type tableau (array: true)
    # default: [] = tableau vide par défaut (jamais nil)
    add_column :stories, :extra_child_ids, :integer, array: true, default: []

    # Rend world_theme optionnel — on utilise désormais la description libre du parent
    # change_column_null(table, column, allow_null?)
    change_column_null :stories, :world_theme, true
  end

  def down
    # Annule les changements dans l'ordre inverse
    change_column_null :stories, :world_theme, false
    remove_column :stories, :extra_child_ids
  end
end
