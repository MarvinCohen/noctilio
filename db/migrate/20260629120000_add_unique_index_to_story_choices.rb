# Migration : garantir l'unicité d'un choix par étape au sein d'une histoire.
# ============================================================
# Contexte : GenerateStoryContinuationJob crée un StoryChoice avec
# step_number = step_number_courant + 1. Si le job est rejoué (retry Solid Queue,
# double soumission, etc.), on pouvait créer DEUX choix pour la même étape de la
# même histoire, ce qui casse l'aventure interactive (deux questions en parallèle).
#
# Cet index unique composite (story_id, step_number) interdit ce doublon au niveau
# base de données : c'est le filet de sécurité ultime, complété côté applicatif par
# une garde d'idempotence dans le job (find_or_create).
class AddUniqueIndexToStoryChoices < ActiveRecord::Migration[8.1]
  def change
    # On remplace l'index simple sur story_id par un index composite unique :
    # un même story_id ne peut plus avoir deux lignes avec le même step_number.
    # L'index composite couvre aussi les requêtes filtrant sur story_id seul
    # (préfixe à gauche), donc on peut retirer l'ancien index devenu redondant.
    remove_index :story_choices, name: "index_story_choices_on_story_id"
    add_index :story_choices, [:story_id, :step_number], unique: true,
              name: "index_story_choices_on_story_id_and_step_number"
  end
end
