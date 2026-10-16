// Détection des messages qui ressemblent à une arnaque (argent, Mobile
// Money, codes reçus, liens) : un avertissement s'affiche sous le message.

// Moins de fausses alertes : « transférer la photo », le prénom Wave ou un
// lien TikTok / YouTube / Instagram ne déclenchent plus « Prudence ».
final _motifArnaque = RegExp(
    r'(mobile ?money|orange ?money|\bmomo\b|moov ?money|mtn ?money|'
    r'\b(par|sur|via|ton|ta|mon|un|compte|num[ée]ro) wave\b|\bwave (moi|me)\b|'
    r"western ?union|moneygram|transf[eé]r\w* (d'|de l')?argent|"
    r'envoie[- ]?moi .*(argent|fcfa|francs|cfa)|'
    r"(pr[eê]te|donne)[- ]?moi .*(argent|fcfa|francs)|\bcode (de |d')?(v[ée]rification|confirmation|re[cç]u)|"
    r'\d[\d .]{2,}\s?(fcfa|f cfa|cfa|francs)|'
    r'https?://(?!(www\.|vm\.|m\.)?(tiktok\.com|youtube\.com|youtu\.be|instagram\.com|facebook\.com|fb\.watch|play\.google\.com))|'
    r'bit\.ly|carte bancaire|crypto|bitcoin)',
    caseSensitive: false);


/// true si le message reçu mérite l'avertissement « Prudence ».
bool messageSuspect(String? texte) =>
    texte != null && texte.length > 3 && _motifArnaque.hasMatch(texte);
