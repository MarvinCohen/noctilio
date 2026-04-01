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
    @story    = Story.new(educational_value: "courage")
    @children = current_user.children.ordered

    # Si l'utilisateur n'a pas encore créé de profil enfant, on le redirige
    if @children.empty?
      redirect_to new_child_path, alert: "Créez d'abord le profil d'un enfant pour générer une histoire !"
    end
  end

  # POST /stories — crée l'histoire et lance la génération en arrière-plan
  def create
    # Récupère les IDs d'enfants sélectionnés (peut en avoir plusieurs)
    # Le premier ID devient l'enfant principal (child_id), les autres sont extra_child_ids
    selected_ids = Array(params[:story][:child_ids]).reject(&:blank?).map(&:to_i)

    if selected_ids.empty?
      @children = current_user.children.ordered
      @story    = Story.new(story_params.except(:child_ids))
      @story.errors.add(:child_id, "Sélectionne au moins un enfant")
      render :new, status: :unprocessable_entity
      return
    end

    # Le premier enfant sélectionné est le héros principal
    primary_child_id = selected_ids.first
    extra_ids        = selected_ids[1..]   # Les autres enfants (peut être vide)

    # On vérifie que tous les enfants appartiennent bien à l'utilisateur connecté
    child = current_user.children.find(primary_child_id)

    # Construit l'histoire avec le premier enfant comme propriétaire
    permitted = story_params.except(:child_ids)
    @story = child.stories.build(permitted)

    # Associe les enfants supplémentaires
    @story.extra_child_ids = current_user.children
                                         .where(id: extra_ids)
                                         .pluck(:id)

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

    # Répond en JSON (requête AJAX depuis story_choice_controller.js)
    # ou en HTML (fallback si JavaScript désactivé)
    respond_to do |format|
      format.json { render json: { success: true } }
      format.html { redirect_to story_path(@story), notice: "Excellent choix ! La suite de l'aventure se prépare... ✨" }
    end
  end

  # GET /stories/:id/status — retourne le statut JSON (pour polling Stimulus)
  def status
    # Récupère la continuation interactive si disponible (mode interactif terminé)
    # Utilisé par story_choice_controller.js pour mettre à jour le texte sans recharger
    continuation_html = nil
    if @story.completed? && @story.interactive?
      resolved = @story.story_choices.where.not(chosen_option: nil).order(:step_number).last
      if resolved&.context_chosen.present?
        # Convertit le markdown généré par l'IA en HTML propre côté serveur
        # Redcarpet est plus fiable que le parser JS artisanal dans story_choice_controller
        renderer = Redcarpet::Render::HTML.new(safe_links_only: true)
        markdown  = Redcarpet::Markdown.new(renderer, autolink: false, tables: false)
        continuation_html = markdown.render(resolved.context_chosen)
      end
    end

    render json: {
      status:       @story.status,
      completed:    @story.completed?,
      title:        @story.title,
      continuation: continuation_html,  # HTML prêt à insérer dans le DOM
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
  # child_ids: [] = tableau d'IDs (sélection multiple d'enfants)
  # extra_child_ids: [] = géré manuellement dans create, pas directement via permit
  def story_params
    params.require(:story).permit(
      :child_id,
      :world_theme,
      :educational_value,
      :reading_level,
      :duration_minutes,
      :custom_theme,
      :interactive,
      child_ids: []     # Tableau d'IDs pour la sélection multiple d'enfants
    )
  end
end
