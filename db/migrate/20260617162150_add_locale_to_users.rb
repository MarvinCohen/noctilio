class AddLocaleToUsers < ActiveRecord::Migration[8.1]
  # Ajoute la colonne `locale` à la table users.
  # Elle mémorise la langue d'interface choisie par un utilisateur connecté
  # (fr, en, es, de, it, pt) afin de la retrouver d'une session à l'autre.
  # default: "fr" → tout compte existant ou nouveau démarre en français,
  #                 la langue par défaut de l'application.
  def change
    add_column :users, :locale, :string, default: "fr"
  end
end
