class AddIndexesToStories < ActiveRecord::Migration[8.1]
  def change
    # Index sur child_id — clé étrangère la plus requêtée (current_user.stories = WHERE child_id IN ...)
    add_index :stories, :child_id unless index_exists?(:stories, :child_id)

    # Index sur status — scope completed/pending/generating utilisé partout
    add_index :stories, :status unless index_exists?(:stories, :status)

    # Index sur saved — scope saved_stories fait WHERE saved = true sur toutes les histoires
    add_index :stories, :saved unless index_exists?(:stories, :saved)

    # Index sur created_at — scope recent fait ORDER BY created_at DESC
    add_index :stories, :created_at unless index_exists?(:stories, :created_at)

    # Index composé (child_id, status) — combinaison la plus fréquente :
    # current_user.stories.completed = WHERE child_id IN (...) AND status = 2
    add_index :stories, [:child_id, :status], name: "index_stories_on_child_id_and_status" unless index_exists?(:stories, [:child_id, :status])
  end
end
