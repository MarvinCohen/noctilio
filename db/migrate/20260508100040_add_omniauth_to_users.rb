class AddOmniauthToUsers < ActiveRecord::Migration[8.1]
  def change
    # provider : nom du fournisseur OAuth (ex: "google_oauth2")
    add_column :users, :provider, :string
    # uid : identifiant unique de l'utilisateur chez le fournisseur OAuth
    add_column :users, :uid, :string

    # Index composite sur provider + uid — utilisé dans User.from_omniauth
    # pour trouver rapidement un utilisateur existant lors du callback OAuth
    add_index :users, [:provider, :uid], unique: true
  end
end
