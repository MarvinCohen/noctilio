class AddImageStyleToStories < ActiveRecord::Migration[8.1]
  def change
    add_column :stories, :image_style, :string
  end
end
