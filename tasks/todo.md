## Objectif

Préparer Noctilio à la commercialisation (hors quotas — gardés désactivés pour les
tests de Marvin). Ordre : sécurité serveur → RGPD → dashboard → page abonnement.

## Étapes

### 1. Gardes serveur (protection du modèle premium)
- [x] story.rb : validation serveur — interactive: true exige un compte premium
      (la checkbox HTML désactivée ne suffit pas, contournable via POST direct)
- [x] stories_controller.rb#audio : exiger premium? (le TTS coûte de l'argent à chaque appel)

### 2. RGPD (obligatoire — données de mineurs)
- [x] Vérifier les associations dependent: :destroy (User → Children → Stories → attachments)
- [x] Bouton "Supprimer mon compte" dans /mon-compte (Devise registrations#destroy + confirmation)
- [x] Case consentement parental obligatoire à la création d'un profil enfant
      (attribut virtuel + validates acceptance)

### 3. Dashboard utile (au lieu de la landing dupliquée)
- [x] Retirer les sections marketing (Comment ça marche / Fonctionnalités / Témoignages)
- [x] Ajouter : dernières histoires (reprendre la lecture) + raccourci enfants

### 4. Page abonnement plus vendeuse
- [x] Tableau comparatif Gratuit vs Premium
- [x] Mini FAQ (facturation, annulation)

### 5. Tests des protections (régression)
- [x] story_test.rb : validation interactive_requires_premium (4 cas : gratuit refusé,
      premium accepté, non-interactif ok, histoire existante reste valide)
- [x] child_test.rb : consentement parental (décoché refusé, coché ok, nil ok, update ok)
- [x] stories_controller_test.rb : POST interactive forgé → 422, audio gratuit → 403
- [x] account_controller_test.rb : page protégée + mode test réservé à la liste blanche

### 6. Analytics — Umami Cloud (gratuit, cookieless)
Décision : Umami Cloud (compte gratuit sur cloud.umami.is, jusqu'à 10k events/mois).
Comportement : script rendu seulement si ENV["UMAMI_WEBSITE_ID"] présent (→ off en dev/test),
jamais pour un admin connecté (n'pollue pas les stats avec le mode test), cookieless (pas de bannière RGPD).

- [x] CSP : autoriser cloud.umami.is dans script_src + connect_src
- [x] AnalyticsHelper#umami_enabled? (ENV présent ET pas admin connecté)
- [x] Partial shared/_analytics.html.erb (balise <script defer> conditionnelle, avec nonce)
- [x] Inclure le partial dans le <head> des layouts application + landing
- [x] Documenter UMAMI_WEBSITE_ID dans CLAUDE.md (projet)
- [x] Test analytics_helper_test.rb (activation/désactivation selon ENV + admin)
- [ ] À faire par Marvin : créer le site sur cloud.umami.is, mettre UMAMI_WEBSITE_ID sur Railway

## Checklist de lancement (jour J)
- [ ] Réactiver les quotas : décommenter check_story_limit! (stories_controller.rb:12-14)
      + réactiver le test "limite mensuelle" désactivé dans stories_controller_test.rb
- [ ] Stripe : créer le produit Premium 9,99€/mois + STRIPE_PREMIUM_PRICE_ID sur Railway
      (mode test d'abord, puis basculer en mode live)
- [ ] Stripe : tester le flux complet checkout → webhook → premium? = true → résiliation
- [ ] Retirer ou vider AUTHORIZED_TEST_EMAILS si le mode test ne doit plus servir en prod
- [ ] Analytics : choisir Plausible (payant, simple) ou Umami (gratuit, auto-hébergé Railway)
- [ ] Vérifier robots.txt / sitemap.xml / Schema.org (voir section dédiée dans CLAUDE.md
      si la landing est remplacée par le dashboard)
- [ ] Tester l'inscription complète en prod : signup → enfant (consentement) → histoire
- [ ] Vérifier les emails Devise en prod (confirmation, reset password)

## Notes
- Quotas (check_story_limit!) : volontairement laissés désactivés — tests en cours
- Analytics : nécessite un compte externe (Plausible/Umami) — à décider avec Marvin
