class AddImageScenePromptToStories < ActiveRecord::Migration[8.1]
  def change
    add_column :stories, :image_scene_prompt, :text
  end
end
