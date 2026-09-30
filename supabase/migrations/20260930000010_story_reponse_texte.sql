-- Réponses aux stories texte : on conserve le texte et la couleur de
-- fond de la story dans le message, pour les afficher dans le chat
-- (une story texte n'a pas d'image d'aperçu).
-- L'app fonctionne sans cette migration (elle réessaie sans ces
-- colonnes), mais le chat n'affiche alors que « Story texte ».

alter table public.messages
  add column if not exists story_text text,
  add column if not exists story_bg_color text;
