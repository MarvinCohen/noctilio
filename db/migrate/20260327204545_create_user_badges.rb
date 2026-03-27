class CreateUserBadges < ActiveRecord::Migration[8.1]
  def change
    create_table :user_badges do |t|
      # Clés étrangères : quel utilisateur a obtenu quel badge
      t.references :user, null: false, foreign_key: true
      t.references :badge, null: false, foreign_key: true

      # Date et heure d'obtention du badge
      t.datetime :earned_at, null: false

      t.timestamps
    end

    # Index unique : un utilisateur ne peut pas avoir le même badge deux fois
    add_index :user_badges, [:user_id, :badge_id], unique: true
  end
end
