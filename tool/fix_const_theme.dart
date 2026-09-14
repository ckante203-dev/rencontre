import 'dart:io';

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    stderr.writeln(
        'Dossier lib/ introuvable. Lance ce script depuis la racine du projet.');
    exit(1);
  }

  final files = libDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  var totalFiles = 0;

  for (final file in files) {
    final source = file.readAsStringSync();
    final fixed = _stripInvalidConst(source);
    if (fixed != source) {
      file.writeAsStringSync(fixed);
      totalFiles++;
      print('Corrigé : ${file.path}');
    }
  }

  print('\nTerminé. $totalFiles fichier(s) modifié(s).');
}

String _stripInvalidConst(String source) {
  final buffer = StringBuffer();
  var i = 0;
  while (i < source.length) {
    if (_matchesWord(source, i, 'const')) {
      final afterConst = i + 5;
      final span = _findConstructSpan(source, afterConst);
      if (span != null) {
        final constructText = source.substring(afterConst, span);
        if (constructText.contains('AppColors.')) {
          i = afterConst;
          continue;
        }
      }
    }
    buffer.write(source[i]);
    i++;
  }
  return buffer.toString();
}

bool _matchesWord(String s, int i, String word) {
  if (i + word.length > s.length) return false;
  if (s.substring(i, i + word.length) != word) return false;
  final before = i > 0 ? s[i - 1] : ' ';
  final afterIdx = i + word.length;
  final after = afterIdx < s.length ? s[afterIdx] : ' ';
  bool isWordChar(String c) => RegExp(r'[A-Za-z0-9_]').hasMatch(c);
  return !isWordChar(before) && !isWordChar(after);
}

int? _findConstructSpan(String s, int start) {
  var i = start;
  while (i < s.length && s[i].trim().isEmpty) i++;
  if (i >= s.length || !RegExp(r'[A-Za-z_]').hasMatch(s[i])) return null;

  while (i < s.length && RegExp(r'[A-Za-z0-9_.]').hasMatch(s[i])) i++;
  while (i < s.length && s[i].trim().isEmpty) i++;
  if (i >= s.length) return null;

  final opener = s[i];
  if (opener != '(' && opener != '[') return i;
  final closer = opener == '(' ? ')' : ']';

  var depth = 0;
  var inString = false;
  String? stringChar;
  var inLineComment = false;
  var inBlockComment = false;

  for (; i < s.length; i++) {
    final c = s[i];
    final prev = i > 0 ? s[i - 1] : '';

    if (inLineComment) {
      if (c == '\n') inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      if (prev == '*' && c == '/') inBlockComment = false;
      continue;
    }
    if (inString) {
      if (c == stringChar && prev != '\\') inString = false;
      continue;
    }
    if (c == '/' && i + 1 < s.length && s[i + 1] == '/') {
      inLineComment = true;
      continue;
    }
    if (c == '/' && i + 1 < s.length && s[i + 1] == '*') {
      inBlockComment = true;
      continue;
    }
    if (c == "'" || c == '"') {
      inString = true;
      stringChar = c;
      continue;
    }
    if (c == opener) depth++;
    if (c == closer) {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return null;
}
