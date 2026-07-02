# ============================================================
# StoryPdfService — génère le PDF téléchargeable d'une histoire
# ============================================================
# But produit : un parent peut archiver / imprimer une histoire terminée.
# On utilise Prawn (100% Ruby, aucun binaire système) : le PDF est construit
# à la main, page par page.
#
# Structure du document :
#   1. Une page de couverture : "Noctilio", le titre de l'histoire,
#      "Une histoire pour <prénom>", et l'illustration si elle existe.
#   2. Le corps de l'histoire : titres de chapitres (## ...) et paragraphes,
#      parsés depuis le contenu markdown généré par l'IA.
#
# Usage : StoryPdfService.new(story).render  → renvoie la chaîne binaire du PDF.
# ============================================================
class StoryPdfService
  # Couleurs de la charte Noctilio (hex sans #, comme attendu par Prawn).
  COULEUR_OR   = "c9a227".freeze # or/doré des accents
  COULEUR_NUIT = "0f1021".freeze # bleu nuit du texte principal

  # story : l'histoire à exporter (doit être terminée — vérifié côté controller).
  def initialize(story)
    @story = story
    # L'enfant héros de l'histoire (pour le sous-titre "Une histoire pour ...").
    @child = story.child
  end

  # ============================================================
  # render — construit le document et renvoie le PDF (chaîne binaire)
  # ============================================================
  def render
    # margin: marge de 56 points (~2 cm) sur les 4 côtés.
    Prawn::Document.new(page_size: "A4", margin: 56) do |pdf|
      construire_couverture(pdf) # page 1
      construire_corps(pdf)      # page(s) suivante(s)
    end.render
  end

  private

  # ============================================================
  # construire_couverture — première page (titre + illustration)
  # ============================================================
  def construire_couverture(pdf)
    # Marque "Noctilio" en haut, centrée et dorée.
    pdf.fill_color COULEUR_OR
    pdf.text "NOCTILIO", size: 14, style: :bold, align: :center, character_spacing: 3

    pdf.move_down 40

    # Titre de l'histoire (repli si jamais il est vide, ce qui ne devrait pas
    # arriver pour une histoire terminée).
    pdf.fill_color COULEUR_NUIT
    titre = winansi(@story.title.presence || "Histoire")
    pdf.text titre, size: 26, style: :bold, align: :center

    pdf.move_down 12

    # Sous-titre "Une histoire pour <prénom de l'enfant>".
    pdf.fill_color COULEUR_OR
    pdf.text "Une histoire pour #{winansi(@child.name)}",
             size: 14, style: :italic, align: :center

    pdf.move_down 30

    # Illustration de couverture si elle est attachée. On l'ignore proprement
    # en cas d'absence ou d'erreur (format non supporté par Prawn = PNG/JPG
    # uniquement, ou téléchargement impossible) pour ne jamais casser l'export.
    inserer_illustration(pdf)
  end

  # ============================================================
  # inserer_illustration — télécharge et insère l'image de couverture
  # ============================================================
  def inserer_illustration(pdf)
    # Rien à faire si aucune image n'est attachée à l'histoire.
    return unless @story.cover_image.attached?

    # download renvoie les octets bruts du fichier (disque en dev, Cloudinary
    # en prod). StringIO les présente comme un flux lisible par Prawn.
    image_io = StringIO.new(@story.cover_image.download)

    # fit: contraint l'image dans une boîte (largeur, hauteur) en gardant le
    # ratio. position: :center la centre horizontalement.
    pdf.image image_io, fit: [400, 400], position: :center
  rescue StandardError => e
    # Format non supporté, téléchargement échoué, etc. : on logue et on continue
    # sans illustration plutôt que de faire échouer tout le PDF.
    Rails.logger.warn("[StoryPdfService] illustration ignorée : #{e.class} — #{e.message}")
  end

  # ============================================================
  # construire_corps — texte de l'histoire sur de nouvelles pages
  # ============================================================
  def construire_corps(pdf)
    # Le corps commence sur une nouvelle page (la couverture reste seule).
    pdf.start_new_page

    pdf.fill_color COULEUR_NUIT

    # On découpe le contenu en blocs (titres de chapitre / paragraphes) via le
    # même principe que le rendu HTML, puis on écrit chaque bloc dans le PDF.
    blocs_de_contenu.each do |bloc|
      if bloc[:type] == :titre
        # Titre de chapitre : plus gros, en gras, doré, avec de l'espace avant.
        pdf.move_down 16
        pdf.fill_color COULEUR_OR
        pdf.text bloc[:texte], size: 16, style: :bold
        pdf.fill_color COULEUR_NUIT
        pdf.move_down 6
      else
        # Paragraphe : texte justifié, interligne confortable pour la lecture.
        pdf.text bloc[:texte], size: 12, align: :justify, leading: 4
        pdf.move_down 10
      end
    end
  end

  # ============================================================
  # blocs_de_contenu — parse le markdown en une liste de blocs typés
  # ============================================================
  # Renvoie un tableau de { type: :titre|:paragraphe, texte: "..." }.
  # Réutilise la même logique de découpe que StoriesHelper#render_story_markdown
  # (retrait du bloc [CHOIX], titres ##, accumulation des paragraphes) mais
  # produit du texte brut nettoyé pour Prawn au lieu de HTML.
  def blocs_de_contenu
    # Retire le bloc interactif [CHOIX]...[FIN CHOIX] (non pertinent en PDF).
    texte = @story.content.to_s.gsub(/\[CHOIX\].*?\[FIN CHOIX\]/m, "").strip

    blocs           = []
    lignes_para     = [] # buffer des lignes du paragraphe en cours

    # Vide le buffer courant en un bloc paragraphe (si non vide).
    vider_paragraphe = lambda do
      next if lignes_para.empty?

      brut = lignes_para.join(" ").strip
      lignes_para = []
      blocs << { type: :paragraphe, texte: winansi(nettoyer_inline(brut)) } if brut.present?
    end

    texte.each_line do |ligne|
      ligne = ligne.rstrip

      if ligne.start_with?("### ", "## ", "# ")
        # Titre détecté : on ferme d'abord le paragraphe courant.
        vider_paragraphe.call
        # Retire les # de tête et l'espace pour ne garder que le libellé.
        libelle = ligne.sub(/\A#+\s*/, "").strip
        blocs << { type: :titre, texte: winansi(nettoyer_inline(libelle)) }
      elsif ligne.empty?
        # Ligne vide = fin de paragraphe.
        vider_paragraphe.call
      else
        # Ligne de contenu : on l'accumule.
        lignes_para << ligne
      end
    end

    # Dernier paragraphe si le texte ne finit pas par une ligne vide.
    vider_paragraphe.call

    blocs
  end

  # ============================================================
  # nettoyer_inline — retire les marqueurs markdown gras/italique
  # ============================================================
  # Les polices Prawn intégrées gèrent le gras via une OPTION (style: :bold),
  # pas des balises dans le texte. On retire donc simplement les **/* pour ne
  # garder que le texte lisible.
  def nettoyer_inline(texte)
    texte.gsub(/\*\*(.+?)\*\*/, '\1') # **gras** → gras
         .gsub(/\*(.+?)\*/, '\1')     # *italique* → italique
  end

  # ============================================================
  # winansi — rend une chaîne compatible avec les polices Prawn intégrées
  # ============================================================
  # Les polices AFM par défaut (Helvetica) n'acceptent que le jeu WinAnsi
  # (Windows-1252) : les accents français passent, mais les emojis ou glyphes
  # exotiques feraient planter Prawn. On encode vers Windows-1252 en supprimant
  # les caractères non représentables, puis on repasse en UTF-8.
  def winansi(texte)
    texte.to_s
         .encode("Windows-1252", invalid: :replace, undef: :replace, replace: "")
         .encode("UTF-8")
  end
end
