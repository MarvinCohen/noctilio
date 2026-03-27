class CreateChildren < ActiveRecord::Migration[8.1]
  def change
    create_table :children do |t|
      # Informations de base de l'enfant
      t.string :name, null: false
      t.integer :age, null: false
      t.string :gender

      # Apparence physique (pour personnaliser l'histoire et les prompts IA)
      t.string :hair_color
      t.string :eye_color
      t.string :skin_tone

      # Description libre de l'enfant (injectée dans le prompt IA)
      t.text :child_description

      # Traits de personnalité et hobbies stockés en JSON
      # Ex: ["courageux", "curieux"] ou ["espace", "dinosaures"]
      t.jsonb :personality_traits, default: []
      t.jsonb :hobbies, default: []

      # Clé étrangère vers l'utilisateur parent
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
