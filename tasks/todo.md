# Plan — Upsell Essentiel → Premium (upgrade en un clic sur les cadenas)

## Objectif
Quand un abonné **Essentiel** rencontre une fonctionnalité réservée à Premium
(lecture audio, mode interactif), lui proposer un **upgrade direct en un clic**
au lieu du message générique actuel qui le renvoie vers la page de tarifs.
But : convertir les abonnés Essentiel (4,99 €) vers Premium (9,99 €) au moment
exact où ils butent sur la limite.

## Constat (déjà en place — RIEN à recoder côté backend)
- `SubscriptionsController#swap_plan` existe (subscriptions_controller.rb:135) :
  fait évoluer l'abonnement Stripe EXISTANT vers Premium (swap + prorata, pas de
  second abonnement). Garde anti double-abonnement déjà présente.
- Route `POST /abonnement/changer-offre` → `subscription_swap` (routes.rb:160).
- `current_user.essentiel?` distingue déjà l'Essentiel du gratuit (user.rb).

## Le manque (uniquement UI)
Aux endroits suivants, un abonné Essentiel voit le MÊME message qu'un compte
gratuit (lien vers `subscription_path`), alors qu'il pourrait passer Premium
en un clic :
- `show.html.erb:340-348` — cadenas lecture audio (branche `else` du `audio_for?`)
- `new.html.erb:411-424` — toggle mode interactif verrouillé (badge "Premium")

## Fichiers impactés
- app/views/stories/show.html.erb (cadenas audio)
- app/views/stories/new.html.erb (cadenas mode interactif)
- config/locales/fr.yml + en.yml + es.yml + pt.yml + de.yml + it.yml (nouvelles clés)

## Comportement cible
- **Compte gratuit** : inchangé → lien vers `subscription_path` (il doit choisir
  une offre, donc on l'envoie à la page de tarifs).
- **Abonné Essentiel** : bouton/lien qui POST vers `subscription_swap`
  → « Passe Premium pour débloquer l'audio » (un clic, prorata Stripe).

## Étapes
- [x] Ajouter 2 clés i18n par langue (6 fichiers) :
      - `story_show.audio_upgrade_essentiel`
      - `wizard.interactive_upgrade_essentiel`
- [x] show.html.erb (cadenas audio, branche else l.340) : si `current_user.essentiel?`
      → `button_to subscription_swap_path, method: :post` ; sinon → `link_to subscription_path`.
- [x] new.html.erb (toggle interactif) : Essentiel → `button_to subscription_swap_path` ;
      gratuit → `link_to subscription_path`.
- [x] Code commenté (règle CLAUDE.md).
- [x] `rails test` vert (318 runs, 0 failures).
- [ ] Test manuel : se mettre en compte Essentiel en local et vérifier les 2 CTA.

## Points à valider avant de coder
- OK pour utiliser `button_to` (POST) sur le cadenas audio (le swap est un POST) ?
  Alternative : un petit lien qui ouvre une confirmation. Je pars sur `button_to`
  stylé comme la pastille actuelle, sauf avis contraire.
- Textes FR proposés : "Passe Premium pour la lecture audio ✦" /
  "Passe Premium pour le mode interactif ✦". À ajuster si tu veux un autre ton.
