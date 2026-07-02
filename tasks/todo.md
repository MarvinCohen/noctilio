# Programme "rendre Noctilio lucrative" (2026-07-02)

Basé sur `tasks/analyse-strategique.md`. On attaque tout SAUF les livres imprimés (POD).
Découpé en incréments livrables (1 incrément = 1 commit/PR cohérent).
Chaque incrément est validé avant de coder.

Légende :
- [CODE] = je le fais entièrement.
- [TOI] = action de Marvin requise (dashboard externe, clés, env Railway). Je ne peux pas la faire.

---

## Ce dont j'ai besoin de toi EN PARALLÈLE (à préparer côté dashboards) — TOUT FAIT le 2026-07-02
Ces éléments débloquent les incréments 4 à 6. Toutes les clés sont posées sur Railway.
- [x] Stripe LIVE : produits/prix Essentiel 4,99€ et Premium 9,99€ en live + prix annuel (-25%),
      price IDs récupérés et mappés sur Railway.
- [x] Stripe : webhook prod vers /pay/webhooks/stripe créé + signing secret (whsec_) posé.
- [x] CAPTCHA : compte hCaptcha créé, site key (HCAPTCHA_SITE_KEY) + secret key posées.
- [x] Clés VAPID : paire générée et posée sur Railway.
- [x] Sentry : projet créé, SENTRY_DSN posé sur Railway.
- [x] Umami : UMAMI_WEBSITE_ID confirmé sur Railway.

---

## Incrément 1 : Protection marge + douceur découverte  [CODE, aucune dépendance]
Objectif : protéger le budget API et adoucir le choc après la 1re histoire.
- [x] Rate limit par user_id (pas juste IP) sur la génération d'histoire, l'audio,
      l'exploration d'alternative (config/initializers/rack_attack.rb).
- [x] Illustrations offertes sur les 3 premières histoires au lieu d'1
      (User#welcome_illustration? / illustrations_for? dans app/models/user.rb).
- [x] Tests : quota par user, illustrations pour les histoires #1 #2 #3, bloquées à #4.

## Incrément 2 : Emails de cycle de vie  [CODE, aucune dépendance]
Objectif : rétention et viralité, le levier le moins cher.
- [~] Mailer "ton histoire est prête" → ABANDONNÉ : l'histoire se génère en <30s
      pendant que le parent est sur la page (polling) → email inutile/spam.
- [x] Open Graph riche (og:title/description/image) sur la page de partage public
      → DÉJÀ FAIT (shared_stories/show.html.erb + layout landing).
- [x] Mailers de relance J+7 et J+30 sans histoire (UserMailer#no_story_reminder)
      + job récurrent Solid Queue (InactiveUserReminderJob) qui scanne les inactifs.
- [x] Tests des mailers + du job de relance.

## Incrément 3 : Mesure du funnel  [CODE, dépend de UMAMI_WEBSITE_ID côté Railway]
Objectif : pouvoir mesurer pour itérer.
- [x] Events Umami custom : signup, story_created, checkout_started, subscription_activated
      (AnalyticsHelper#umami_event_tag + liste blanche ; flash[:umami_event] posé
      dans Users::RegistrationsController#create, StoriesController#create,
      SubscriptionsController#success ; clic checkout_started via data-umami-event
      sur les 2 boutons de la page abonnement).
- [x] Vérifier que les events ne partent pas en dev/test/admin
      (umami_event_tag rend vide si umami_enabled? est false + liste blanche anti-injection).

## Incrément 4 : Pricing (annuel + essai)  [CODE + TOI pour les price IDs]  ✅ FAIT
Objectif : +LTV et +conversion Premium.
- [x] Toggle Mensuel/Annuel sur la page abonnement, -25% sur l'annuel
      (Stimulus pricing_toggle_controller ; prix mensuel/annuel en data-attributes).
- [x] Essai 7 jours étendu à Premium (option A retenue : essai gratuit, pas 0,99€).
- [x] SubscriptionsController#checkout résout le bon price ID selon plan + période
      (checkout_price_id(plan, period) + checkout_period whitelist anti-injection).
- [x] Tests du routage des price IDs (essentiel/premium annuel + fallback mensuel).

## Incrément 5 : Stripe LIVE + anti-abus signup  [CODE + TOI pour clés]
Objectif : encaisser réellement + bloquer les bots.
- [ ] CAPTCHA hCaptcha au signup (gem + intégration Devise registrations).
- [ ] Rate limit signup par IP renforcé.
- [ ] Bascule des clés Stripe en live (côté env Railway = TOI ; code prêt = moi).
- [ ] Vérifier la validation de signature du webhook (config/initializers/pay.rb).

## Incrément 6 : Rétention push + monitoring  [CODE + TOI pour VAPID/Sentry]
Objectif : boucle d'habitude quotidienne + visibilité erreurs.
- [ ] Scheduler "rituel du soir" : job récurrent qui envoie le push le soir,
      à l'heure d'activité habituelle du parent, avec frequency capping (1/jour).
- [ ] Activer Sentry en prod (code prêt, DSN posé par TOI).
- [ ] Tests du job de rappel push.

## Incrément 7 : Export PDF de l'histoire  [CODE, aucune dépendance]
Objectif : conservation/archivage (parents veulent garder les histoires).
- [x] Bouton "Télécharger en PDF" sur la page histoire (gem prawn, 100% Ruby,
      aucun binaire système à installer sur Railway). Ouvert à tous (pas Premium).
- [x] Mise en page : couverture (titre + prénom + illustration) + texte parsé
      depuis le markdown (StoryPdfService). Route GET /stories/:id/pdf.
- [x] Tests : service (%PDF non vide + contenu piégeux) + controller
      (200 PDF pour owner terminé, refus si non terminé, blocage cross-user).

## Incrément 8 : Personnages récurrents persistants  [CODE, feature moyenne]
Objectif : attachement et rétention (+40% observé sur le marché).
- [ ] Modèle pour un compagnon/personnage sauvegardé et réutilisable entre histoires.
- [ ] Injection du personnage dans le prompt texte + image.
- [ ] UI de sélection au moment de la création.
- [ ] Tests.

## Incrément 9 : Mode hors-ligne  [CODE, plus technique]
Objectif : lecture en voiture/avion.
- [ ] Service worker : cache des histoires lues (texte + images + audio).
- [ ] UI "disponible hors-ligne".
- [ ] Tests manuels.

---

## Ordre proposé
1, 2, 3, 7 d'abord (code pur, aucune dépendance externe, gros impact rétention/marge).
En parallèle tu prépares Stripe live / hCaptcha / VAPID / Sentry.
Puis 4, 5, 6 (dès que les clés sont prêtes).
Puis 8 et 9 (features plus lourdes).

Chaque incrément : plan détaillé -> code commenté -> tests verts -> commit.
Pas de push sans que tu le demandes.
