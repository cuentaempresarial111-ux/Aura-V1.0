import 'dart:math' as math;

/// Returns the Shannon entropy, in bits per character, of [value].
double calculateShannonEntropy(String value) {
  if (value.isEmpty) return 0;

  final counts = <int, int>{};
  for (final codeUnit in value.toLowerCase().codeUnits) {
    counts.update(codeUnit, (count) => count + 1, ifAbsent: () => 1);
  }

  final length = value.length;
  return -counts.values.fold<double>(0, (entropy, count) {
    final probability = count / length;
    return entropy + probability * (math.log(probability) / math.ln2);
  });
}
