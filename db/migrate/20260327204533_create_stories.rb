class CreateStories < ActiveRecord::Migration[8.1]
  def change
    create_table :stories do |t|
      # Titre généré par l'IA
      t.string :title

      # Contenu complet de l'histoire (texte long généré par GPT)
      t.text :content

      # Univers de l'histoire : space, dinos, princesses, pirates, animals
      t.string :world_theme, null: false

      # Valeur éducative transmise : courage, sharing, kindness, confidence
      t.string :educational_value

      # Niveau de lecture : beginner ou intermediate
      t.string :reading_level, default: "beginner"

      # Durée cible en minutes : 5, 10, ou 15
      t.integer :duration_minutes, default: 5

      # Thème personnalisé libre saisi par le parent
      t.text :custom_theme

      # Statut de génération :
      # 0 = pending (en attente), 1 = generating (en cours),
      # 2 = completed (terminé), 3 = failed (erreur)
      t.integer :status, default: 0, null: false

      # Si true : l'histoire propose des choix interactifs pendant la lecture
      t.boolean :interactive, default: false, null: false

      # URL temporaire de l'image DALL-E (expire après 1h — téléchargée en job)
      t.string :cover_image_url

      # Prompt utilisé pour générer l'image (utile pour régénérer)
      t.text :image_prompt

      # Clé étrangère vers l'enfant pour qui l'histoire est créée
      t.references :child, null: false, foreign_key: true

      t.timestamps
    end

    # Index pour récupérer rapidement les histoires par statut
    add_index :stories, :status
  end
end
