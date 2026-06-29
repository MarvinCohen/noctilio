class AddImageSceneToStories < ActiveRecord::Migration[8.1]
  def change
    add_column :stories, :image_scene, :text
  end
end
