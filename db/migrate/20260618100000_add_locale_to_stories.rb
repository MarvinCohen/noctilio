class AddLocaleToStories < ActiveRecord::Migration[8.1]
  # Ajoute la colonne `locale` à la table stories.
  # Elle FIGE la langue de chaque histoire au moment de sa création
  # (fr, en, es, de, it, pt).
  #
  # Pourquoi figer la langue sur l'histoire plutôt que la relire à la volée ?
  # La génération du texte tourne dans un job Solid Queue, en arrière-plan,
  # où I18n.locale revient toujours à :fr (la langue par défaut). On ne peut
  # donc PAS connaître la langue de l'utilisateur depuis le job. En la stockant
  # sur la Story dès la création (controller), le service de génération et les
  # jobs de suite/relecture/partage la retrouvent de façon fiable.
  #
  # default: "fr"   → toute histoire existante ou créée sans locale explicite
  #                   démarre en français (langue par défaut de l'app).
  # null: false     → on garantit qu'une histoire a TOUJOURS une langue connue,
  #                   ce qui évite un cas nil à gérer côté service IA.
  def change
    add_column :stories, :locale, :string, default: "fr", null: false
  end
end
