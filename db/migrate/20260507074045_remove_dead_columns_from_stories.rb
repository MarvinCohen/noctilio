class RemoveDeadColumnsFromStories < ActiveRecord::Migration[8.1]
  # ============================================================
  # Supprime deux colonnes jamais utilisées dans le code :
  #   — image_prompt  : colonne morte, logique gérée par image_scene_prompt
  #   — reading_level : feature abandonnée, valeur par défaut "beginner" inutilisée
  # La méthode up supprime, la méthode down restaure (migration réversible)
  # ============================================================
  def up
    remove_column :stories, :image_prompt
    remove_column :stories, :reading_level
  end

  def down
    # Restaure les colonnes si on revient en arrière
    add_column :stories, :image_prompt,  :string
    add_column :stories, :reading_level, :string, default: "beginner"
  end
end
