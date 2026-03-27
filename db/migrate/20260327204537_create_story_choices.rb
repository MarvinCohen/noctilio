class CreateStoryChoices < ActiveRecord::Migration[8.1]
  def change
    create_table :story_choices do |t|
      # Numéro de l'étape dans l'histoire (1er choix, 2ème choix...)
      t.integer :step_number, null: false, default: 1

      # Question posée à l'enfant (ex: "Que doit faire Léo ?")
      t.text :question, null: false

      # Les deux options proposées
      t.text :option_a, null: false
      t.text :option_b, null: false

      # Option choisie par l'enfant ('a' ou 'b') — nil si pas encore choisi
      t.string :chosen_option

      # Suite de l'histoire générée après le choix
      t.text :context_chosen

      # Clé étrangère vers l'histoire
      t.references :story, null: false, foreign_key: true

      t.timestamps
    end
  end
end
