class AddAdminToUsers < ActiveRecord::Migration[8.1]
  def change
    # Par défaut false — aucun utilisateur n'est admin sans intervention manuelle
    add_column :users, :admin, :boolean, default: false, null: false
  end
end
