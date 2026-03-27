class CreateBadges < ActiveRecord::Migration[8.1]
  def change
    create_table :badges do |t|
      # Nom affiché du badge (ex: "Première Histoire")
      t.string :name, null: false

      # Description affichée dans la Trophy Room
      t.text :description

      # Emoji ou classe d'icône (ex: "⭐", "🦉")
      t.string :icon

      # Clé unique identifiant la condition d'obtention
      # Ex: "first_story", "five_stories", "night_owl"
      t.string :condition_key, null: false

      t.timestamps
    end

    # Index unique pour éviter les doublons de condition_key
    add_index :badges, :condition_key, unique: true
  end
end
