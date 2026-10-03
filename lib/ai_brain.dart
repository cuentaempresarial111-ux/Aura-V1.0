import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'agent/aura_crypto_layer.dart';
import 'agent/aura_whitelist.dart';
import 'secure_vault.dart';
import 'providers/aura_state_provider.dart';

typedef AuraToolStartedCallback = void Function(
  String toolName,
  Map<String, Object?> arguments,
);
typedef AuraToolCompletedCallback = void Function(
  String toolName,
  Map<String, Object?> arguments,
  Map<String, Object?> result,
);
typedef AuraDnsBlockRuleHandler = Future<bool> Function(String domain);

const Set<String> _suspiciousTlds = {
  'cam',
  'click',
  'country',
  'date',
  'download',
  'fit',
  'gq',
  'loan',
  'mov',
  'party',
  'review',
  'rest',
  'stream',
  'support',
  'tk',
  'top',
  'wang',
  'work',
  'xyz',
  'zip',
};

const Set<String> _domainFieldNames = {
  'domain',
  'host',
  'hostname',
  'qname',
  'requested_domain',
};

final RegExp _domainPattern = RegExp(
  r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9-]{1,63})+',
);

double calculateShannonEntropy(String core) {
  if (core.isEmpty) return 0;
  final counts = <int, int>{};
  for (final codeUnit in core.toLowerCase().codeUnits) {
    counts.update(codeUnit, (count) => count + 1, ifAbsent: () => 1);
  }
  final length = core.length;
  return -counts.values.fold<double>(0, (entropy, count) {
    final probability = count / length;
    return entropy + probability * (math.log(probability) / math.ln2);
  });
}

List<double> extractFeatures(String domain) {
  final host = _normalizeDomain(domain);
  final characters = host.runes.toList(growable: false);
  final letters = characters
      .where(_isAsciiLetter)
      .toList(growable: false);
  final digits = characters.where(_isAsciiDigit).length;
  final vowels = letters.where(_isVowel).length;
  final consonantSequenceCharacters = _consonantSequenceLength(characters);
  final tld = host.split('.').last;
  final letterCount = letters.length;

  return <double>[
    host.length.toDouble(),
    calculateShannonEntropy(host),
    characters.isEmpty ? 0 : digits / characters.length,
    letterCount == 0 ? 0 : vowels / letterCount,
    letterCount == 0 ? 0 : consonantSequenceCharacters / letterCount,
    _suspiciousTlds.contains(tld) ? 1 : 0,
  ];
}

class AuraAIBrain {
  static const String _modelAssetPath =
  'assets/model/aura_brain_model.enc';
  static const MethodChannel _engineChannel =
      MethodChannel('com.aura.cyberdefense/engine');
  static const MethodChannel _shieldChannel =
      MethodChannel('com.ciberdefensa.aura/shield');
  static final List<WeakReference<AuraAIBrain>> _instances = [];

  final AuraStateProvider? _stateProvider;
  final AuraSecureVault _secureVault;
  final AuraToolStartedCallback? _onToolStarted;
  final AuraToolCompletedCallback? _onToolCompleted;
  AuraDnsBlockRuleHandler? _onDnsBlockRule;
  Future<Map<String, dynamic>>? _modelLoad;

  AuraAIBrain({
    AuraStateProvider? stateProvider,
    AuraSecureVault? secureVault,
    AuraToolStartedCallback? onToolStarted,
    AuraToolCompletedCallback? onToolCompleted,
    AuraDnsBlockRuleHandler? onDnsBlockRule,
    })  : _stateProvider = stateProvider,
      _secureVault = secureVault ?? AuraSecureVault(),
        _onToolStarted = onToolStarted,
        _onToolCompleted = onToolCompleted,
        _onDnsBlockRule = onDnsBlockRule {
    _instances.removeWhere((reference) => reference.target == null);
    _instances.add(WeakReference<AuraAIBrain>(this));
  }

  void setDnsBlockRuleHandler(AuraDnsBlockRuleHandler handler) {
    _onDnsBlockRule = handler;
  }

  Future<bool> setShieldActive(bool active) async {
    final result = await _shieldChannel.invokeMethod<bool>(
      active ? 'startShield' : 'stopShield',
    );
    return result ?? false;
  }

  Future<bool> addDnsBlockRule(String domain) async {
    final handler = _onDnsBlockRule;
    if (handler != null) return handler(domain);
    final result = await _engineChannel.invokeMethod<bool>(
      'addDnsBlockRule',
      {'domain': domain},
    );
    return result ?? false;
  }

  Future<String> analyzeCyberThreat(String userInput) =>
      analyzeThreatPayload(userInput);

  Future<void> preloadModel() async {
    await (_modelLoad ??= _loadModel());
  }

  static Future<void> purgeAllInMemoryModels() async {
    final brains = _instances
        .map((reference) => reference.target)
        .whereType<AuraAIBrain>()
        .toList(growable: false);
    for (final brain in brains) {
      await brain._purgeCachedModel();
    }
    _instances.removeWhere((reference) => reference.target == null);
  }

  Future<void> _purgeCachedModel() async {
    final cachedLoad = _modelLoad;
    _modelLoad = null;
    if (cachedLoad == null) return;
    try {
      _clearModelValue(await cachedLoad);
    } on Object {
      return;
    }
  }

  void _clearModelValue(Object? value) {
    if (value is Map) {
      for (final nestedValue in value.values.toList(growable: false)) {
        _clearModelValue(nestedValue);
      }
      value.clear();
    } else if (value is List) {
      for (final nestedValue in value.toList(growable: false)) {
        _clearModelValue(nestedValue);
      }
      value.clear();
    }
  }

  Future<String> analyzeThreatPayload(String payload) async {
    final domains = _extractDomains(payload);
    if (domains.isEmpty) {
      return 'Análisis local limitado a dominios: no se encontró un dominio válido.';
    }

    try {
      final results = <String>[];
      for (final domain in domains) {
        if (AuraWhitelist.isSafe(domain)) {
          results.add(
            'Dominio seguro por allowlist: $domain (0% de votos de amenaza).',
          );
          continue;
        }

        final model = await (_modelLoad ??= _loadModel());
        final features = extractFeatures(domain);
        final trees = model['trees'];
        if (trees is! List || trees.length != 500) {
          throw const FormatException('El bosque local no contiene árboles.');
        }
        var threatVotes = 0;
        for (final tree in trees) {
          if (tree is! Map || !tree.containsKey('root')) {
            throw const FormatException('Raíz de árbol inválida en el bosque local.');
          }
          threatVotes += _evaluateNode(
            Map<String, dynamic>.from(tree)['root'],
            features,
          );
        }
        final threatScore = threatVotes / trees.length;
        final isThreat = threatScore >= 0.5;
        _stateProvider?.recordLocalForestEvaluation();

        if (isThreat) {
          _stateProvider?.setSecurityLevel(AuraSecurityLevel.critical);
          final arguments = <String, Object?>{'domain': domain};
          _onToolStarted?.call('mitigate_network_threat', arguments);
          Map<String, Object?> result;
          try {
            final blocked = await addDnsBlockRule(domain);
            result = {
              'ok': blocked,
              'domain': domain,
              'enforcement_scope': 'device-wide',
              if (!blocked) 'error': 'El motor no confirmó la regla DNS.',
            };
          } on Object catch (error) {
            result = {
              'ok': false,
              'domain': domain,
              'error': error.toString(),
            };
          }
          _onToolCompleted?.call(
            'mitigate_network_threat',
            arguments,
            result,
          );
          results.add(
            'AMENAZA: $domain (${(threatScore * 100).toStringAsFixed(0)}% '
            'de votos); ${result['ok'] == true ? 'bloqueo confirmado' : 'bloqueo no confirmado'}.',
          );
        } else {
          results.add(
            'Sin amenaza según el modelo local: $domain '
            '(${(threatScore * 100).toStringAsFixed(0)}% de votos de amenaza).',
          );
        }
      }
      return results.join('\n');
    } on Object catch (error) {
      return 'ERROR DE ANÁLISIS LOCAL: ${error.toString()}';
    }
  }

  Future<Map<String, dynamic>> _loadModel() async {
    final encryptedHex = await rootBundle.loadString(_modelAssetPath);
    final secureKey = await _secureVault.getOrCreateModelMasterKey();
    final encoded = AuraCryptoLayer.decryptModel(encryptedHex, secureKey);
    final decoded = jsonDecode(encoded);
    if (decoded is! Map ||
      decoded['trees'] is! List ||
      (decoded['trees'] as List).length != 500) {
      throw const FormatException('El modelo local no contiene un bosque válido.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  int _evaluateNode(Object? rawNode, List<double> features) {
    if (rawNode is! Map) {
      throw const FormatException('Nodo inválido en el modelo local.');
    }
    final node = Map<String, dynamic>.from(rawNode);
    if (node['type'] == 'leaf') {
      final value = node['value'];
      if (value is! int || (value != 0 && value != 1)) {
        throw const FormatException('La hoja debe contener un voto binario.');
      }
      return value;
    }
    if (node['type'] != 'split' ||
        node['feature_index'] is! int ||
        node['threshold'] is! num) {
      throw const FormatException('Nodo de bifurcación inválido.');
    }

    final featureIndex = node['feature_index'] as int;
    if (featureIndex < 0 || featureIndex >= features.length) {
      throw const FormatException('Índice de característica fuera de rango.');
    }
    final branch = features[featureIndex] <=
            (node['threshold'] as num).toDouble()
        ? node['left']
        : node['right'];
    return _evaluateNode(branch, features);
  }

  List<String> _extractDomains(String payload) {
    final domains = <String>{};
    try {
      _collectDomains(jsonDecode(payload), domains);
    } on FormatException {
      for (final match in _domainPattern.allMatches(payload)) {
        final value = match.group(0);
        if (value != null) domains.add(_normalizeDomain(value));
      }
    }
    return domains.where((domain) => domain.contains('.')).toList();
  }

  void _collectDomains(Object? value, Set<String> domains) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().toLowerCase();
        if (_domainFieldNames.contains(key) && entry.value is String) {
          final domain = _normalizeDomain(entry.value as String);
          if (domain.contains('.')) domains.add(domain);
        } else {
          _collectDomains(entry.value, domains);
        }
      }
    } else if (value is List) {
      for (final entry in value) {
        _collectDomains(entry, domains);
      }
    }
  }
}

String _normalizeDomain(String input) {
  var candidate = input.trim().toLowerCase();
  if (candidate.contains('://')) {
    candidate = Uri.tryParse(candidate)?.host ?? candidate;
  } else {
    candidate = candidate.split('/').first;
    candidate = candidate.split(':').first;
  }
  return candidate.replaceFirst(RegExp(r'\.$'), '');
}

bool _isAsciiLetter(int character) =>
    (character >= 65 && character <= 90) ||
    (character >= 97 && character <= 122);

bool _isAsciiDigit(int character) => character >= 48 && character <= 57;

bool _isVowel(int character) => 'aeiou'.codeUnits.contains(character);

int _consonantSequenceLength(List<int> characters) {
  var runLength = 0;
  var sequenceCharacters = 0;
  for (final character in characters) {
    if (_isAsciiLetter(character) && !_isVowel(character)) {
      runLength++;
    } else {
      if (runLength >= 3) sequenceCharacters += runLength;
      runLength = 0;
    }
  }
  if (runLength >= 3) sequenceCharacters += runLength;
  return sequenceCharacters;
}
