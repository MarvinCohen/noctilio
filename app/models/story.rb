class Story < ApplicationRecord
  # ============================================================
  # Associations
  # ============================================================

  # Une histoire appartient à un enfant spécifique
  belongs_to :child

  # Une histoire peut avoir plusieurs choix interactifs
  # (supprimés automatiquement si l'histoire est supprimée)
  has_many :story_choices, dependent: :destroy

  # Relation saga — une histoire peut être la suite d'une autre
  # parent_story : l'épisode précédent (nil si c'est le 1er épisode)
  belongs_to :parent_story, class_name: "Story", optional: true
  # sequel_stories : toutes les histoires qui ont été créées comme suite de celle-ci
  has_many :sequel_stories, class_name: "Story", foreign_key: :parent_story_id, dependent: :nullify

  # Image de couverture stockée dans ActiveStorage
  has_one_attached :cover_image

  # Fichier audio MP3 généré par OpenAI TTS via GenerateAudioJob
  has_one_attached :audio_file

  # ============================================================
  # Enum — statuts de génération
  # ============================================================
  # pending    : l'histoire vient d'être créée, le job n'a pas encore démarré
  # generating : le job est en cours, l'IA génère le contenu
  # completed  : l'histoire est prête à être lue
  # failed     : une erreur s'est produite pendant la génération
  enum :status, { pending: 0, generating: 1, completed: 2, failed: 3 }

  # ============================================================
  # Validations
  # ============================================================
  # world_theme est optionnel — la description libre du parent remplace l'univers prédéfini
  validates :child_id,     presence: true
  validates :status,       presence: true
  validates :duration_minutes, inclusion: { in: [5, 10, 15] }, allow_nil: true

  # ============================================================
  # Scopes
  # ============================================================

  # Histoires terminées uniquement
  scope :completed, -> { where(status: :completed) }

  # Histoires les plus récentes en premier
  scope :recent, -> { order(created_at: :desc) }

  # Histoires complétées et triées par date
  scope :completed_recent, -> { completed.recent }

  # Histoires sauvegardées par l'utilisateur dans sa bibliothèque
  # Utilisé dans StoriesController#index pour n'afficher que les histoires gardées
  scope :saved_stories, -> { where(saved: true) }

  # ============================================================
  # Méthodes métier
  # ============================================================

  # Retourne l'emoji correspondant à l'univers de l'histoire
  # Retourne ✨ si pas d'univers prédéfini (mode description libre)
  def world_emoji
    {
      "space"      => "🚀",
      "dinos"      => "🦕",
      "princesses" => "👸",
      "pirates"    => "🏴‍☠️",
      "animals"    => "🦁"
    }.fetch(world_theme.to_s, "✨")
  end

  # Retourne le libellé français de l'univers
  # Si pas d'univers prédéfini, retourne un extrait de la description libre
  def world_label
    {
      "space"      => "Espace",
      "dinos"      => "Dinosaures",
      "princesses" => "Princesses",
      "pirates"    => "Pirates",
      "animals"    => "Animaux"
    }.fetch(world_theme.to_s, custom_theme.presence || "Histoire personnalisée")
  end

  # Retourne les enfants supplémentaires associés à cette histoire
  # extra_child_ids est un tableau d'IDs PostgreSQL stocké en base
  def extra_children
    return Child.none if extra_child_ids.blank?
    Child.where(id: extra_child_ids)
  end

  # Retourne tous les enfants de l'histoire (principal + supplémentaires)
  def all_children
    [child] + extra_children.to_a
  end

  # Retourne le prochain choix interactif non encore effectué
  # Retourne nil si tous les choix ont été faits ou si non interactive
  def next_choice
    story_choices.where(chosen_option: nil).order(:step_number).first
  end

  # Retourne true si l'histoire a des choix en attente
  def has_pending_choice?
    interactive? && next_choice.present?
  end

  # ============================================================
  # Méthodes saga — épisodes liés
  # ============================================================

  # Retourne true si cette histoire est la suite d'une autre
  def sequel?
    parent_story_id.present?
  end

  # Remonte la chaîne jusqu'au tout premier épisode de la saga
  # Utile pour regrouper les épisodes dans la bibliothèque
  def root_story
    sequel? ? parent_story.root_story : self
  end

  # Calcule le numéro d'épisode en remontant la chaîne des parents
  # Épisode 1 = histoire sans parent, Épisode 2 = suite directe, etc.
  def episode_number
    sequel? ? parent_story.episode_number + 1 : 1
  end

  # Retourne tous les épisodes de la saga dans l'ordre chronologique
  # Commence depuis le 1er épisode et descend jusqu'aux suites
  def saga_episodes
    root_story.all_sequels_in_order
  end

  # Retourne true si une suite a déjà été créée pour cette histoire
  def has_sequel?
    sequel_stories.exists?
  end

  # ============================================================

  # Retourne l'URL de l'image de couverture
  # — Si ActiveStorage a l'image : on utilise la version stockée
  # — Sinon : on utilise l'URL temporaire OpenAI (peut expirer)
  def cover_image_source
    if cover_image.attached?
      cover_image
    else
      cover_image_url
    end
  end

  protected

  # Construit la liste ordonnée de tous les épisodes à partir de celui-ci
  # Récursif : descend dans les suites jusqu'à la fin de la saga
  def all_sequels_in_order
    [self] + sequel_stories.order(:created_at).flat_map(&:all_sequels_in_order)
  end
end
