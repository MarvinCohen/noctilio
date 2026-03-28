class StoriesController < ApplicationController
  # ============================================================
  # Controller des histoires — création, lecture, suppression
  # ============================================================

  # Charge l'histoire avant ces actions
  # save_story est inclus pour récupérer @story via set_story avant de la sauvegarder
  before_action :set_story, only: [:show, :destroy, :choose, :status, :save_story]

  # Vérifie la limite d'histoires AVANT de créer (gratuit : 3/mois max)
  before_action :check_story_limit!, only: [:new, :create]

  # GET /stories — bibliothèque personnelle de l'utilisateur
  def index
    # N'affiche que les histoires terminées ET sauvegardées par l'utilisateur
    # Une histoire doit être explicitement sauvegardée pour apparaître ici
    @stories = current_user.stories.completed_recent.saved_stories
  end

  # GET /stories/:id — lecture de l'histoire
  def show
    # Si l'histoire est encore en cours de génération, la page affiche un spinner
    # Le statut est vérifié via polling JavaScript (StoryStatusController Stimulus)

    # Prochain choix interactif non effectué (nil si non interactive ou terminé)
    @pending_choice = @story.next_choice if @story.completed?
  end

  # GET /stories/new — formulaire de création
  def new
    # Pré-sélectionne des valeurs par défaut pour éviter les erreurs de validation
    # si l'utilisateur soumet sans avoir cliqué sur chaque option
    @story    = Story.new(world_theme: "space", educational_value: "courage")
    @children = current_user.children.ordered

    # Si l'utilisateur n'a pas encore créé de profil enfant, on le redirige
    if @children.empty?
      redirect_to new_child_path, alert: "Créez d'abord le profil d'un enfant pour générer une histoire !"
    end
  end

  # POST /stories — crée l'histoire et lance la génération en arrière-plan
  def create
    # On trouve l'enfant concerné (doit appartenir à l'utilisateur)
    child = current_user.children.find(story_params[:child_id])
    @story = child.stories.build(story_params)

    if @story.save
      # Lance le job de génération en arrière-plan via Solid Queue
      # L'histoire aura le statut "pending" jusqu'à ce que le job commence
      GenerateStoryJob.perform_later(@story.id)

      # Redirige vers la page de l'histoire (qui affichera le spinner)
      redirect_to story_path(@story), notice: "La magie opère... votre histoire est en cours de création ! ✨"
    else
      @children = current_user.children.ordered
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to new_story_path, alert: "Profil enfant introuvable."
  end

  # POST /stories/:id/choose — enregistre le choix interactif de l'enfant
  def choose
    # Vérification : l'histoire doit être terminée et interactive
    unless @story.completed? && @story.interactive?
      redirect_to story_path(@story), alert: "Cette histoire n'a pas de choix interactif."
      return
    end

    # Récupère le choix en attente
    pending_choice = @story.next_choice
    unless pending_choice
      redirect_to story_path(@story), alert: "Il n'y a plus de choix à effectuer."
      return
    end

    # Valide que le choix est 'a' ou 'b'
    chosen = params[:chosen_option]
    unless %w[a b].include?(chosen)
      redirect_to story_path(@story), alert: "Choix invalide."
      return
    end

    # Enregistre le choix
    pending_choice.update!(chosen_option: chosen)

    # Marque l'histoire comme "en génération" pour la suite
    @story.update!(status: :generating)

    # Lance le job pour générer la suite de l'histoire
    GenerateStoryContinuationJob.perform_later(@story.id, pending_choice.id)

    redirect_to story_path(@story), notice: "Excellent choix ! La suite de l'aventure se prépare... ✨"
  end

  # GET /stories/:id/status — retourne le statut JSON (pour polling Stimulus)
  def status
    render json: {
      status: @story.status,
      completed: @story.completed?,
      title: @story.title,
      redirect_url: story_path(@story)
    }
  end

  # POST /stories/:id/save — sauvegarde l'histoire dans la bibliothèque de l'utilisateur
  # Marque saved: true pour que l'histoire apparaisse dans l'index (bibliothèque)
  def save_story
    # Met à jour le flag saved en base — update! lève une exception si ça échoue
    @story.update!(saved: true)
    # Redirige vers la page de l'histoire avec un message de confirmation
    redirect_to story_path(@story), notice: "Histoire sauvegardée dans ta bibliothèque ! 📚"
  end

  # DELETE /stories/:id — supprime l'histoire
  def destroy
    @story.destroy
    redirect_to stories_path, notice: "L'histoire a été supprimée."
  end

  private

  # Charge l'histoire depuis les histoires de l'utilisateur connecté
  # (via ses enfants) — évite qu'un utilisateur accède aux histoires d'un autre
  def set_story
    @story = current_user.stories.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to stories_path, alert: "Histoire introuvable."
  end

  # Paramètres autorisés pour la création d'une histoire
  def story_params
    params.require(:story).permit(
      :child_id,
      :world_theme,
      :educational_value,
      :reading_level,
      :duration_minutes,
      :custom_theme,
      :interactive
    )
  end
end
