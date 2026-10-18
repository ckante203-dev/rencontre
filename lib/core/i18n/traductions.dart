import 'dart:ui';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rencontre/core/i18n/en_auto.dart';

/// Langues de l'application. Un texte sans clé traduite reste en français
/// (fallbackLocale) : on traduit l'app écran par écran.
/// Une langue proposée dans l'app.
class LangueDispo {
  final String code; // code ISO à 2 lettres, aussi enregistré dans profiles.langue
  final Locale locale;
  final String nom; // dans la langue elle-même (« Español »)
  final String drapeau;
  const LangueDispo(this.code, this.locale, this.nom, this.drapeau);
}

class Langue {
  static const fr = Locale('fr', 'FR');
  static const en = Locale('en', 'US');
  static const _cle = 'langue';

  /// Langues proposées (menus de l'inscription et des Paramètres). Ajouter
  /// une langue : une ligne ici + son dictionnaire dans [Traductions] (+ ses
  /// textes « il y a … » dans main.dart si timeago les connaît).
  static const disponibles = [
    LangueDispo('fr', fr, 'Français', '🇫🇷'),
    LangueDispo('en', en, 'English', '🇬🇧'),
  ];

  static LangueDispo _parCode(String? code) => disponibles.firstWhere(
      (l) => l.code == code,
      orElse: () => disponibles.first);

  /// Langue enregistrée, sinon celle du téléphone si l'app la propose,
  /// sinon le français.
  static Locale initiale() {
    final code = GetStorage().read<String>(_cle) ??
        PlatformDispatcher.instance.locale.languageCode;
    return _parCode(code).locale;
  }

  /// Code de la langue affichée (« fr », « en »…).
  static String get code => _parCode(Get.locale?.languageCode).code;

  /// Langue affichée (nom et drapeau pour les menus).
  static LangueDispo get actuelle => _parCode(Get.locale?.languageCode);

  static Future<void> changer(String code) async {
    final locale = _parCode(code).locale;
    await GetStorage().write(_cle, locale.languageCode);
    await Get.updateLocale(locale);
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'langue': locale.languageCode}).eq('id', uid);
    } catch (_) {
      // Colonne absente ou hors ligne : la langue reste enregistrée localement.
    }
  }
}

class Traductions extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
        'fr_FR': _fr,
        'en_US': {...enAuto, ..._en},
      };
}

const _fr = {
  // ── Commun ──
  'commun.ou': 'ou',
  'commun.email': 'Email',
  'commun.email_hint': 'ton@email.com',
  'commun.mot_de_passe': 'Mot de passe',
  'commun.google': 'Continuer avec Google',
  'commun.apple': 'Continuer avec Apple',
  'commun.cgu': "Conditions d'utilisation",
  'commun.confidentialite': 'Politique de confidentialité',
  'commun.se_connecter': 'Se connecter',

  // ── Connexion ──
  'connexion.titre': 'Connexion',
  'connexion.sous_titre': 'Connecte-toi pour retrouver tes matchs',
  'connexion.identifiant': "Email ou nom d'utilisateur",
  'connexion.identifiant_hint': 'ton@email.com ou ton pseudo',
  'connexion.oublie': 'Mot de passe oublié ?',
  'connexion.bouton': 'Se connecter →',
  'connexion.pas_de_compte': 'Pas encore de compte ?',
  'connexion.inscrire': "S'inscrire",
  'connexion.liens_legaux':
      "Conditions d'utilisation · Politique de confidentialité",
  'connexion.oublie_texte':
      "On t'envoie un lien de réinitialisation par email.",
  'connexion.envoyer_lien': 'Envoyer le lien',

  // ── Inscription ──
  'inscription.titre': 'Crée ton\ncompte 🚀',
  'inscription.sous_titre': 'Rejoins des milliers de personnes autour de toi',
  'inscription.prenom': 'Prénom',
  'inscription.prenom_hint': 'Ton prénom',
  'inscription.mdp_hint': 'Min. 8 caractères',
  'inscription.bouton': 'Créer mon compte →',
  'inscription.deja_compte': 'Déjà un compte ? ',
  'inscription.accepte': 'En créant un compte, tu acceptes nos ',
  'inscription.et_notre': ' et notre ',
  'inscription.pseudo': "Nom d'utilisateur (facultatif)",
  'inscription.pseudo_hint': 'ex: sarah.k',
  'inscription.verification': 'Vérification...',
  'inscription.disponible': 'Disponible',
  'inscription.deja_pris': 'Déjà pris',
  'inscription.confirmer_mdp': 'Confirmer le mot de passe',
  'inscription.confirmer_mdp_hint': 'Répète ton mot de passe',
  'inscription.mdp_ok': 'Les mots de passe correspondent',
  'inscription.mdp_ko': 'Les mots de passe ne correspondent pas',
  'inscription.naissance': 'DATE DE NAISSANCE',
  'inscription.naissance_hint': 'JJ / MM / AAAA',

  // ── Paramètres ──
  'parametres.langue': 'Langue',
};

const _en = {
  'Vidéos en lecture auto': 'Autoplay videos',
  'Aussi en données mobiles (sinon Wi-Fi seulement)': 'Also on mobile data (otherwise Wi-Fi only)',
  // ── Suppression différée ──
  "Ton compte sera masqué tout de suite, puis supprimé définitivement dans 30 jours (profil, photos, messages, matchs). Tu changes d'avis ? Reconnecte-toi avant la fin des 30 jours pour le garder.":
      "Your account will be hidden right away, then permanently deleted in 30 days (profile, photos, messages, matches). Changed your mind? Log in again within 30 days to keep it.",
  'Compte masqué': 'Account hidden',
  'Il sera supprimé définitivement dans 30 jours.': 'It will be permanently deleted in 30 days.',
  'Il sera supprimé définitivement le @date.': 'It will be permanently deleted on @date.',
  'Garder ton compte ?': 'Keep your account?',
  'Tu as demandé la suppression de ton compte. Il est masqué et sera supprimé définitivement le @date.':
      'You asked to delete your account. It is hidden and will be permanently deleted on @date.',
  'Continuer la suppression': 'Continue deletion',
  'Garder mon compte': 'Keep my account',
  'Bon retour 💜': 'Welcome back 💜',
  'Ton compte est de nouveau visible.': 'Your account is visible again.',
  // ── Vérifier mon e-mail / coller le code ──
  'Vérifier mon e-mail': 'Verify my email',
  'E-mail vérifié': 'Email verified',
  'E-mail vérifié ✅': 'Email verified ✅',
  "Protège ton compte : on t'envoie un code": "Protect your account: we'll send you a code",
  'Entre le code reçu à @email (regarde aussi dans les spams).': 'Enter the code sent to @email (check your spam too).',
  "On envoie un code à @email pour confirmer que c'est bien ton adresse.": "We'll send a code to @email to confirm it's your address.",
  'Coller le code': 'Paste code',
  'Rien à coller': 'Nothing to paste',
  "Copie d'abord le code depuis l'e-mail (appui long sur le code)": 'First copy the code from the email (long-press the code)',
  // ── Date de naissance manquante ──
  'Erreur de connexion. Réessaie.': 'Connection error. Try again.',
  'Ta date de naissance 🎂': 'Your date of birth 🎂',
  "Elle n'a pas été enregistrée à ton inscription. Ton âge s'affichera sur ton profil (tu peux masquer ta date dans les paramètres).":
      "It wasn't saved when you signed up. Your age will show on your profile (you can hide your date in settings).",
  'Zamu est réservé aux 18 ans et plus': 'Zamu is for people aged 18 and over',
  'Tu ne peux pas utiliser Zamu avant tes 18 ans.': "You can't use Zamu until you're 18.",
  // ── Mot de passe oublié (code par e-mail) ──
  'Entre le code reçu à @email (regarde aussi dans les spams), puis ton nouveau mot de passe.':
      'Enter the code sent to @email (check your spam too), then your new password.',
  "On t'envoie un code par email pour choisir un nouveau mot de passe.":
      "We'll email you a code to choose a new password.",
  'Code reçu par email': 'Code from the email',
  'Nouveau mot de passe': 'New password',
  'Changer mon mot de passe': 'Change my password',
  'Envoyer le code': 'Send code',
  'Renvoyer le code': 'Resend code',
  'Entre le code reçu par email': 'Enter the code from the email',
  'Le mot de passe doit faire au moins 8 caractères': 'Password must be at least 8 characters',
  'Mot de passe modifié ✅': 'Password changed ✅',
  'Tu es connecté avec ton nouveau mot de passe': "You're logged in with your new password",
  'Code incorrect ou expiré. Renvoie un nouveau code.': 'Wrong or expired code. Send a new one.',
  "Choisis un mot de passe différent de l'ancien.": 'Choose a password different from the old one.',
  'Trop de demandes. Réessaie dans quelques minutes.': 'Too many requests. Try again in a few minutes.',
  // ── Thèmes ──
  'Thèmes': 'Themes',
  'Classiques': 'Classic',
  'Illustrés': 'Illustrated',
  'De saison': 'Seasonal',
  'Appliquer le thème': 'Apply theme',
  'Thème actuel ✓': 'Current theme ✓',
  'Cerise noire': 'Black cherry',
  'Indigo': 'Indigo',
  "Lettre d'amour": 'Love letter',
  'Lagune': 'Lagoon',
  'Nuit étoilée': 'Starry night',
  'Fêtes': 'Holidays',
  'Système': 'System',
  'Sombre': 'Dark',
  'Clair': 'Light',
  'Réactiver les notifications': 'Turn notifications back on',
  'Quitter le groupe': 'Leave group',
  'Bienvenue sur Zamu !': 'Welcome to Zamu!',
  'Tu as @h h de Premium offertes': 'You have @h h of free Premium',
  'Vois qui t\'a liké et qui a vu ton profil': 'See who liked you and who viewed your profile',
  'Jusqu\'à 600 profils': 'Up to 600 profiles',
  'Ton profil mis en avant': 'Your profile boosted',
  'Voir qui m\'a liké': 'See who liked me',
  'Plus tard': 'Later',
  'Ajoute une photo où l\'on voit ton visage': 'Add a photo that shows your face',
  'Vérifie ton profil (badge bleu ✓)': 'Verify your profile (blue badge ✓)',
  'Le message disparaît aussi chez l\'autre personne': 'The message also disappears for the other person',
  'Il reste visible chez l\'autre personne': 'It stays visible for the other person',
  '◀ Glisse pour annuler · ▲ pour verrouiller': '◀ Slide to cancel · ▲ to lock',
  'Qui veux-tu rencontrer ?': 'Who do you want to meet?',
  'Tu verras seulement les personnes qui te cherchent aussi. Ce choix reste privé.':
      'You will only see people who are looking for you too. This choice stays private.',
  "Personne croisée pour l'instant": 'Nobody crossed yet',
  // ── Parrainage généreux (SQL 064) ──
  'Rejoins-moi sur Zamu 💬 À l\'inscription, entre mon code @pseudo : tu gagnes 24 h de Premium offertes ⚡\nhttps://play.google.com/store/apps/details?id=com.vybestyle.zamu':
      'Join me on Zamu 💬 When you sign up, enter my code @pseudo: you get 24 h of free Premium ⚡\nhttps://play.google.com/store/apps/details?id=com.vybestyle.zamu',
  'Code accepté ⚡ 24 h de Premium pour toi, 7 jours pour ton ami !':
      'Code accepted ⚡ 24 h of Premium for you, 7 days for your friend!',
  'Ton code : @@pseudo. Chaque ami inscrit avec ton code te donne 7 jours de Premium (24 h pour lui).':
      'Your code: @@pseudo. Each friend who signs up with your code gives you 7 days of Premium (24 h for them).',
  // ── Common ──
  'commun.ou': 'or',
  'commun.email': 'Email',
  'commun.email_hint': 'you@email.com',
  'commun.mot_de_passe': 'Password',
  'commun.google': 'Continue with Google',
  'commun.apple': 'Continue with Apple',
  'commun.cgu': 'Terms of Use',
  'commun.confidentialite': 'Privacy Policy',
  'commun.se_connecter': 'Log in',

  // ── Login ──
  'connexion.titre': 'Log in',
  'connexion.sous_titre': 'Log in to find your matches',
  'connexion.identifiant': 'Email or username',
  'connexion.identifiant_hint': 'you@email.com or your username',
  'connexion.oublie': 'Forgot password?',
  'connexion.bouton': 'Log in →',
  'connexion.pas_de_compte': "Don't have an account yet?",
  'connexion.inscrire': 'Sign up',
  'connexion.liens_legaux': 'Terms of Use · Privacy Policy',
  'connexion.oublie_texte': "We'll send you a reset link by email.",
  'connexion.envoyer_lien': 'Send link',

  // ── Sign up ──
  'inscription.titre': 'Create your\naccount 🚀',
  'inscription.sous_titre': 'Join thousands of people around you',
  'inscription.prenom': 'First name',
  'inscription.prenom_hint': 'Your first name',
  'inscription.mdp_hint': 'At least 8 characters',
  'inscription.bouton': 'Create my account →',
  'inscription.deja_compte': 'Already have an account? ',
  'inscription.accepte': 'By creating an account, you accept our ',
  'inscription.et_notre': ' and our ',
  'inscription.pseudo': 'Username (optional)',
  'inscription.pseudo_hint': 'e.g. sarah.k',
  'inscription.verification': 'Checking...',
  'inscription.disponible': 'Available',
  'inscription.deja_pris': 'Already taken',
  'inscription.confirmer_mdp': 'Confirm password',
  'inscription.confirmer_mdp_hint': 'Repeat your password',
  'inscription.mdp_ok': 'Passwords match',
  'inscription.mdp_ko': 'Passwords do not match',
  'inscription.naissance': 'DATE OF BIRTH',
  'inscription.naissance_hint': 'DD / MM / YYYY',

  // ── Settings ──
  'parametres.langue': 'Language',
};
