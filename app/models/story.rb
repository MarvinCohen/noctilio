class Story < ApplicationRecord
  # ============================================================
  # Associations
  # ============================================================

  # Une histoire appartient à un enfant spécifique
  belongs_to :child

  # Une histoire peut avoir plusieurs choix interactifs
  # (supprimés automatiquement si l'histoire est supprimée)
  has_many :story_choices, dependent: :destroy

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
end
