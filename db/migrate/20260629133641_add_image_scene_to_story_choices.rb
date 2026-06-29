class AddImageSceneToStoryChoices < ActiveRecord::Migration[8.1]
  # Ajoute la phrase de scène (anglais) du moment fort de CHAQUE suite interactive.
  # Pendant : equivalent de stories.image_scene mais au niveau du StoryChoice, pour
  # générer une illustration fidèle à la suite (et pas seulement à l'intro).
  def change
    add_column :story_choices, :image_scene, :text
  end
end
