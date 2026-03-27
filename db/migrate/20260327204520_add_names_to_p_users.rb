class AddNamesToPUsers < ActiveRecord::Migration[8.1]
  # Ajoute le prénom et le nom de famille à la table users
  # Ces champs servent à personnaliser l'expérience et les emails
  def change
    add_column :users, :first_name, :string
    add_column :users, :last_name, :string
  end
end
