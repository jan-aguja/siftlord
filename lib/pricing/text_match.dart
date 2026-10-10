// Loose title matching, tolerant of how sellers write product names
// ("AirPods Pro3", "airpods pro 3", "iPad (11th Generation)").

/// Maps "fancy" Unicode letters sellers use for emphasis back to plain ASCII:
/// mathematical bold/italic/script/… letters and digits ("𝑨𝑰𝑹𝑷𝑶𝑫𝑺 𝟑" →
/// "AIRPODS 3") and fullwidth forms ("ＡｉｒＰｏｄｓ").
String foldStyledLetters(String s) {
  final out = StringBuffer();
  for (final cp in s.runes) {
    if (cp >= 0x1D400 && cp <= 0x1D6A3) {
      final i = (cp - 0x1D400) % 52;
      out.writeCharCode(i < 26 ? 0x41 + i : 0x61 + i - 26);
    } else if (cp >= 0x1D7CE && cp <= 0x1D7FF) {
      out.writeCharCode(0x30 + (cp - 0x1D7CE) % 10);
    } else if (cp >= 0xFF01 && cp <= 0xFF5E) {
      out.writeCharCode(cp - 0xFF01 + 0x21);
    } else {
      out.writeCharCode(cp);
    }
  }
  return out.toString();
}

/// Lowercase, letters and digits split apart ("pro3" → "pro 3"), punctuation
/// dropped.
String normalizeText(String s) {
  var t = foldStyledLetters(s).toLowerCase();
  t = t.replaceAllMapped(RegExp(r'([a-z])(\d)'), (m) => '${m[1]} ${m[2]}');
  t = t.replaceAllMapped(RegExp(r'(\d)([a-z])'), (m) => '${m[1]} ${m[2]}');
  return t.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

List<String> words(String s) {
  final n = normalizeText(s);
  return n.isEmpty ? const [] : n.split(' ');
}

/// Words that say nothing about which product someone wants.
const _noise = {'original', 'authentic', 'genuine', 'new', 'sale', 'legit', 'the', 'and', 'with'};

/// The words of a search that a listing title has to contain.
List<String> queryTokens(String query) =>
    [for (final w in words(query)) if (!_noise.contains(w)) w];

/// True when [title] has every token: numbers as whole words, other tokens
/// also as a word prefix ("gen" matches "generation").
bool titleHasTokens(List<String> titleWords, List<String> tokens) {
  if (tokens.isEmpty) return false;
  for (final t in tokens) {
    final isNumber = RegExp(r'^\d+$').hasMatch(t);
    final hit = titleWords.any((w) => w == t || (!isNumber && t.length >= 3 && w.startsWith(t)));
    if (!hit) return false;
  }
  return true;
}

/// Words that mark a listing as an accessory for the product rather than the
/// product itself.
const accessoryWords = {
  'case', 'cases', 'cover', 'covers', 'strap', 'straps', 'band', 'bands', 'tips',
  'protector', 'tempered', 'film', 'skin', 'sticker', 'pouch', 'holder', 'stand',
  'cable', 'charger', 'adapter', 'replacement', 'compatible', 'sleeve', 'lid',
  'straw', 'for',
};

/// Accessory words that knockoffs also use ("For Original AirPods Pro…"), so
/// they don't excuse a listing from a price alert.
const _knockoffWords = {'for', 'compatible', 'replacement'};

/// True when the title declares itself an accessory with a word the searcher
/// didn't use (searching "airpods case" shouldn't exclude cases), or contains
/// one of the product's own [excludePhrases]. With [strict] false, the words
/// knockoffs also use don't count.
bool looksLikeAccessory(List<String> titleWords, List<String> queryWords,
    {List<String> excludePhrases = const [], bool strict = true}) {
  bool counts(String w) =>
      accessoryWords.contains(w) && !queryWords.contains(w) && (strict || !_knockoffWords.contains(w));
  for (final (i, w) in titleWords.indexed) {
    // "AirPods Pro 3 with MagSafe Charging Case" is the product itself.
    if (w == 'case' && i > 0 && titleWords[i - 1] == 'charging') continue;
    if (counts(w)) return true;
  }
  final title = ' ${titleWords.join(' ')} ';
  for (final phrase in excludePhrases) {
    final p = normalizeText(phrase);
    if (p.isNotEmpty && title.contains(' $p ') && !queryWords.join(' ').contains(p)) {
      return true;
    }
  }
  return false;
}

/// Words that introduce what a listing is made for: "Case for AirPods",
/// "Compatible with MacBook", "Fits iPhone".
const _madeForMarkers = {'for', 'compatible', 'fits', 'fit'};

/// True when the title says it's made *for* the product rather than being it:
/// a marker word followed, within a few words, by the product's first word
/// ("For Original AirPods Pro2…", "65W charger for MacBook"). Doesn't fire
/// when the searcher used the marker themselves ("case for airpods").
bool saysMadeFor(List<String> titleWords, List<String> productTokens, List<String> queryWords) {
  if (productTokens.isEmpty) return false;
  final head = productTokens.first;
  for (final (i, w) in titleWords.indexed) {
    if (!_madeForMarkers.contains(w) || queryWords.contains(w)) continue;
    final window = titleWords.skip(i + 1).take(4);
    if (window.any((x) => x == head || (head.length >= 3 && x.startsWith(head)))) return true;
  }
  return false;
}
