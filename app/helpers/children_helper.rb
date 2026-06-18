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
    # --- Mapping couleurs de cheveux (clé stable → hex DiceBear) ---
    hair_map = {
      "black" => "0e0e0e",
      "dark_brown" => "3d2314",
      "brown" => "6b3a22",
      "dark_blonde" => "9c6f2a",
      "blonde" => "c9a84c",
      "light_blonde" => "e8d5a3",
      "red" => "8b3a0f",
      "white" => "ece8e0"
    }

    # --- Mapping teintes de peau (clé stable → hex DiceBear) ---
    skin_map = {
      "ebony" => "2d1b0e",
      "dark_brown" => "4a2c12",
      "brown" => "7c4a1e",
      "caramel" => "c68a4a",
      "golden" => "d4a853",
      "olive" => "c4a882",
      "beige" => "e8c99a",
      "light" => "f5deb3",
      "very_light" => "fef0e7"
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
