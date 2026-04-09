class AddParentStoryIdToStories < ActiveRecord::Migration[8.1]
  def change
    # Ajoute la clé étrangère optionnelle vers l'histoire parente (épisode précédent)
    # null: true car une histoire peut ne pas avoir de parent (c'est l'épisode 1 d'une saga)
    add_column :stories, :parent_story_id, :integer, null: true

    # Index pour retrouver rapidement toutes les suites d'une histoire
    add_index :stories, :parent_story_id
  end

  def down
    # Retrait propre — index d'abord, puis colonne
    remove_index :stories, :parent_story_id
    remove_column :stories, :parent_story_id
  end
end
