require "test_helper"

# ============================================================
# Tests du StoryPdfService — génération du PDF d'une histoire
# ============================================================
# On ne vérifie pas le rendu visuel (impossible en test unitaire), mais le
# CONTRAT : le service produit bien un document PDF non vide, et il ne plante
# pas sur les cas piégeux (markdown, bloc [CHOIX], caractères hors WinAnsi).
class StoryPdfServiceTest < ActiveSupport::TestCase
  # Un vrai fichier PDF commence toujours par la signature "%PDF".
  # C'est le moyen le plus fiable de vérifier qu'on a bien produit un PDF.
  test "render produit un document PDF non vide" do
    # Arrange — une histoire terminée avec du contenu
    story = stories(:completed_saved)

    # Act
    pdf = StoryPdfService.new(story).render

    # Assert — présence de la signature PDF et taille non triviale
    assert pdf.start_with?("%PDF"), "La sortie doit être un vrai PDF (signature %PDF)"
    assert pdf.bytesize > 500, "Le PDF ne doit pas être quasi vide"
  end

  # Le service doit gérer sans planter le markdown (titres ##), le bloc interactif
  # [CHOIX]...[FIN CHOIX] et les caractères non représentables par les polices
  # Prawn intégrées (emoji), qui sont normalement supprimés par winansi.
  test "render gère le markdown, le bloc CHOIX et les caractères spéciaux" do
    # Arrange — on injecte un contenu piégeux sur une histoire terminée
    story = stories(:completed_saved)
    story.update!(content: <<~CONTENU)
      ## Chapitre 1

      Il était une fois **Léo**, un héros courageux 🚀 qui rêvait d'étoiles.

      [CHOIX]
      Question : Que fait Léo ?
      Option A : Partir
      Option B : Rester
      [FIN CHOIX]

      ## Chapitre 2

      Et l'aventure continua avec *émerveillement*.
    CONTENU

    # Act + Assert — aucune exception ne doit être levée, et on obtient un PDF
    pdf = nil
    assert_nothing_raised do
      pdf = StoryPdfService.new(story).render
    end
    assert pdf.start_with?("%PDF"), "Le PDF doit être généré malgré le contenu piégeux"
  end
end
