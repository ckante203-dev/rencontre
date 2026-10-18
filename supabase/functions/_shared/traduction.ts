// Traduction des notifications envoyées par le serveur.
//
// Les textes des relances, rappels d'événements, « Croisés » et bilans de
// Boost sont fabriqués en français par des fonctions SQL. Avant l'envoi, on
// les traduit selon la langue choisie dans l'app (profiles.langue). Une
// phrase sans traduction connue part en français (comme avant).
//
// Ajouter une langue : un tableau de règles de plus dans REGLES.

import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

type Regle = [RegExp, string];

const EN: Regle[] = [
  // relances_du_jour
  [/^💬 1 message t'attend$/, "💬 1 message is waiting for you"],
  [/^💬 (\d+) messages t'attendent$/, "💬 $1 messages are waiting for you"],
  [/^Réponds avant que la conversation refroidisse 😉$/, "Reply before the conversation goes cold 😉"],
  [/^👀 1 personne a vu ton profil$/, "👀 1 person viewed your profile"],
  [/^👀 (\d+) personnes ont vu ton profil$/, "👀 $1 people viewed your profile"],
  [/^Découvre qui s'intéresse à toi$/, "See who's interested in you"],
  [/^🙋 1 personne près de toi est dispo$/, "🙋 1 person near you is free"],
  [/^🙋 (\d+) personnes près de toi sont dispo$/, "🙋 $1 people near you are free"],
  [/^Café, sortie, discussion… vois qui est partant$/, "Coffee, going out, a chat… see who's up for it"],
  [/^📸 (\d+) nouvelles stories$/, "📸 $1 new stories"],
  [/^Depuis ta dernière visite sur Zamu$/, "Since your last visit to Zamu"],
  // notifs_evenements_a_envoyer
  [/^📅 Demain : (.+)$/s, "📅 Tomorrow: $1"],
  [/^Tu y vas \? Retrouve les participants avant d'y être 👀$/, "Going? Meet the other attendees before you get there 👀"],
  [/^⏰ Bientôt : (.+)$/s, "⏰ Coming up: $1"],
  [/^Ça commence dans moins de 2 h\. Arrivé \? Touche « Je suis sur place » 📍$/, "It starts in less than 2 h. Arrived? Tap \"I'm there\" 📍"],
  [/^💘 1 personne que tu as likée va à (.+)$/s, "💘 1 person you liked is going to $1"],
  [/^💘 (\d+) personnes que tu as likées vont à (.+)$/s, "💘 $1 people you liked are going to $2"],
  [/^Dis « J'y vais » pour les retrouver sur place$/, "Tap \"I'm going\" to meet them there"],
  [/^(\S+) Nouvel événement : (.+)$/s, "$1 New event: $2"],
  [/^(\d\d\/\d\d) à (\d\dh\d\d) · (.*)$/s, "$1 at $2 · $3"],
  // croises_a_notifier
  [/^👋 Tu as croisé du monde à (.+)$/s, "👋 You crossed paths with people at $1"],
  [/^Quelqu'un était aussi là\. Dis-lui bonjour !$/, "Someone else was there too. Say hi!"],
  [/^(.+) était aussi là\. Dis-lui bonjour !$/s, "$1 was there too. Say hi!"],
  [/^(.+) et 1 autre étaient aussi là\. Dis-leur bonjour !$/s, "$1 and 1 other person were there too. Say hi!"],
  [/^(.+) et (\d+) autres étaient aussi là\. Dis-leur bonjour !$/s, "$1 and $2 others were there too. Say hi!"],
  // Bilan de Boost (rappel-evenements)
  [/^⚡ Ton Boost est terminé$/, "⚡ Your Boost has ended"],
  [/^Découvre ton bilan et relance un Boost ⚡$/, "See your results and start another Boost ⚡"],
  [/^👀 (\d+) vues? · ❤️ (\d+) likes?(?: — ×([\d,]+) que d'habitude)?$/, "👀 $1 views · ❤️ $2 likes BOOST_X$3"],
];

const REGLES: Record<string, Regle[]> = { en: EN };

/** Texte traduit dans [langue], ou le texte d'origine (français). */
export function traduire(texte: string, langue: string | null | undefined): string {
  const regles = REGLES[langue ?? "fr"];
  if (!regles || !texte) return texte;
  for (const [motif, remplacement] of regles) {
    if (!motif.test(texte)) continue;
    let r = texte.replace(motif, remplacement);
    // Bilan de Boost : « ×1,8 que d'habitude » → « 1.8× more than usual »
    r = r.replace(/ BOOST_X([\d,]+)$/, (_, x) => ` — ${x.replace(",", ".")}× more than usual`)
      .replace(/ BOOST_X$/, "")
      .replace(/^👀 1 views/, "👀 1 view")
      .replace(/❤️ 1 likes/, "❤️ 1 like");
    return r;
  }
  return texte;
}

/** Langue de chaque destinataire (profiles.langue), « fr » par défaut. */
export async function languesDe(
  admin: SupabaseClient, ids: string[],
): Promise<Map<string, string>> {
  const langues = new Map<string, string>();
  const uniques = [...new Set(ids.filter(Boolean))];
  for (let i = 0; i < uniques.length; i += 300) {
    const { data, error } = await admin.from("profiles")
      .select("id, langue")
      .in("id", uniques.slice(i, i + 300));
    if (error) break; // colonne absente : tout le monde en français
    for (const p of data ?? []) langues.set(p.id, p.langue ?? "fr");
  }
  return langues;
}
