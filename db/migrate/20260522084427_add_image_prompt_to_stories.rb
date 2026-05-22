class AddImagePromptToStories < ActiveRecord::Migration[8.1]
  def change
    add_column :stories, :image_prompt, :text
  end
end
