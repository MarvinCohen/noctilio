# ============================================================
# ChildrenHelper — méthodes utilitaires pour les vues children
# ============================================================

module ChildrenHelper
  # Génère l'URL de l'avatar DiceBear personnalisé selon le profil de l'enfant.
  #
  # On utilise le style "adventurer" qui supporte skin + hair color.
  # Le seed (prénom) garantit un avatar stable et unique par enfant.
  # Les couleurs viennent directement des valeurs saisies dans le formulaire.
  #
  # @param child [Child] l'objet enfant avec ses attributs
  # @return [String] URL complète de l'avatar SVG DiceBear
  def dicebear_avatar_url(child)
    # --- Mapping couleurs de cheveux (libellé FR → hex DiceBear) ---
    hair_map = {
      "noir" => "0e0e0e",
      "châtain foncé" => "3d2314",
      "châtain" => "6b3a22",
      "blond foncé" => "9c6f2a",
      "blond" => "c9a84c",
      "blond clair" => "e8d5a3",
      "roux" => "8b3a0f",
      "blanc" => "ece8e0"
    }

    # --- Mapping teintes de peau (libellé FR → hex DiceBear) ---
    skin_map = {
      "ébène" => "2d1b0e",
      "brun foncé" => "4a2c12",
      "brun" => "7c4a1e",
      "caramel" => "c68a4a",
      "doré" => "d4a853",
      "olive" => "c4a882",
      "beige" => "e8c99a",
      "clair" => "f5deb3",
      "très clair" => "fef0e7"
    }

    # Récupère les hex correspondants — fallback sur valeurs neutres si attribut absent
    hair_hex = hair_map[child.hair_color] || "6b3a22"   # châtain par défaut
    skin_hex = skin_map[child.skin_tone]  || "e8c99a"   # beige par défaut

    # Fond sombre cohérent avec la DA Noctilio
    bg_hex = "111527"

    # Filtre les styles de cheveux selon le genre
    # Garçon → cheveux courts (short01 à short04)
    # Fille  → cheveux longs (long01 à long08)
    # Sans genre renseigné → pas de filtre, DiceBear choisit selon le seed
    hair_styles = case child.gender
                  when "boy"  then "short01,short02,short03,short04"
                  when "girl" then "long01,long02,long03,long04,long05,long06,long07,long08"
                  end

    # Construit l'URL DiceBear v9 avec les paramètres de personnalisation
    # seed = prénom → avatar stable et unique par enfant
    # backgroundType=solid → fond plat (pas de dégradé)
    # scale=90 → léger zoom pour que le visage remplisse mieux le cercle
    url  = "https://api.dicebear.com/9.x/adventurer/svg"
    url += "?seed=#{CGI.escape(child.name)}"
    url += "&skinColor=#{skin_hex}"
    url += "&hairColor=#{hair_hex}"
    url += "&backgroundColor=#{bg_hex}"
    url += "&backgroundType=solid"
    url += "&scale=90"
    # DiceBear attend des paramètres hair[] séparés pour chaque style autorisé
    hair_styles&.split(",")&.each { |s| url += "&hair[]=#{s}" }
    url
  end
end
