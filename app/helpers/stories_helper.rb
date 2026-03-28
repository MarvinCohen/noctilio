module StoriesHelper
  # ============================================================
  # Convertit le contenu markdown d'une histoire en HTML propre
  # ============================================================
  # Traitement ligne par ligne pour gérer les cas où le LLM met
  # un titre (## Chapitre) et son paragraphe avec UN seul saut de ligne.
  # split("\n\n") ne suffit pas car le LLM n'est pas toujours cohérent.
  #
  # Gère :
  #   ## Chapitre 1 → <h2 class="story-chapter">
  #   **texte**     → <strong>texte</strong>
  #   *texte*       → <em>texte</em>
  #   Paragraphes   → <p class="story-paragraph">
  def render_story_markdown(content)
    return "".html_safe if content.blank?

    # Retire le bloc [CHOIX]...[FIN CHOIX] (géré séparément)
    text = content.gsub(/\[CHOIX\].*?\[FIN CHOIX\]/m, "").strip

    html_parts       = []
    paragraph_lines  = []  # Buffer pour accumuler les lignes d'un paragraphe courant

    text.each_line do |line|
      line = line.rstrip  # Supprime l'espace et le \n en fin de ligne

      if line.start_with?("## ", "# ", "### ")
        # --- Titre de chapitre détecté ---
        # On flush d'abord le paragraphe en cours avant le titre
        flush_paragraph(paragraph_lines, html_parts)

        # Extrait le niveau et le texte du titre
        if line.start_with?("### ")
          html_parts << tag.h3(line[4..].strip, class: "story-section")
        elsif line.start_with?("## ")
          html_parts << tag.h2(line[3..].strip, class: "story-chapter")
        else
          # # titre → même style que ##
          html_parts << tag.h2(line[2..].strip, class: "story-chapter")
        end

      elsif line.empty?
        # --- Ligne vide = fin de paragraphe ---
        flush_paragraph(paragraph_lines, html_parts)

      else
        # --- Ligne de contenu — on l'accumule dans le paragraphe courant ---
        paragraph_lines << line
      end
    end

    # Flush du dernier paragraphe si le texte ne se termine pas par une ligne vide
    flush_paragraph(paragraph_lines, html_parts)

    html_parts.join("\n").html_safe
  end

  private

  # Transforme les lignes accumulées en un <p> et les vide
  def flush_paragraph(lines, html_parts)
    return if lines.empty?

    # Rejoint les lignes avec un espace (le LLM peut couper les lignes)
    raw = lines.join(" ").strip
    lines.clear

    return if raw.empty?

    # Applique le gras/italique inline après avoir échappé le HTML (sécurité XSS)
    formatted = html_escape(raw)
      .gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
      .gsub(/\*(.+?)\*/, '<em>\1</em>')

    html_parts << tag.p(formatted.html_safe, class: "story-paragraph")
  end
end
