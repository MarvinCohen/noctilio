class AddContextAlternativeToStoryChoices < ActiveRecord::Migration[8.1]
  def change
    # Stocke la continuation "timeline alternative" générée si l'enfant explore l'autre choix
    # null: true car ce texte n'existe que si l'enfant a cliqué sur "Et si j'avais choisi..."
    add_column :story_choices, :context_alternative, :text, null: true
  end

  def down
    remove_column :story_choices, :context_alternative
  end
end
