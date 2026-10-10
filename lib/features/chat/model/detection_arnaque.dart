// Détection des messages qui ressemblent à une arnaque (argent, Mobile
// Money, codes reçus, liens) : un avertissement s'affiche sous le message.

final _motifArnaque = RegExp(
    r'(mobile ?money|orange ?money|\bmomo\b|\bwave\b|moov ?money|mtn ?money|'
    r'western ?union|moneygram|transf[eé]r|envoie[- ]?moi .*(argent|fcfa|francs|cfa)|'
    r"(pr[eê]te|donne)[- ]?moi .*(argent|fcfa|francs)|\bcode (de |d')?(v[ée]rification|confirmation|re[cç]u)|"
    r'\d[\d .]{2,}\s?(fcfa|f cfa|cfa|francs)|https?://|bit\.ly|carte bancaire|crypto|bitcoin)',
    caseSensitive: false);


/// true si le message reçu mérite l'avertissement « Prudence ».
bool messageSuspect(String? texte) =>
    texte != null && texte.length > 3 && _motifArnaque.hasMatch(texte);
