import 'dart:ffi';
import 'dart:typed_data';

import 'package:aura_mobile_defens/secure_memory.dart';
import 'package:test/test.dart';

void main() {
  group('AuraSecureMem.processSecureData', () {
    test('preserves payload bytes and isolates mutations from the source', () {
      final source = Uint8List.fromList([0x10, 0x20, 0x30]);

      final result = AuraSecureMem.processSecureData<String>(
        rawData: source,
        action: (pointer, length) {
          expect(pointer, isNot(nullptr));
          expect(length, source.length);
          expect(List<int>.generate(length, (index) => pointer[index]), source);
          pointer[0] = 0xff;
          return 'processed';
        },
      );

      expect(result, 'processed');
      expect(source, [0x10, 0x20, 0x30]);
    });

    test('preserves arbitrary payload bytes, including zero and 0xff', () {
      final payload = Uint8List.fromList(
        List<int>.generate(256, (index) => index),
      );

      AuraSecureMem.processSecureData<void>(
        rawData: payload,
        action: (pointer, length) {
          expect(length, payload.length);
          for (var index = 0; index < length; index++) {
            expect(pointer[index], payload[index], reason: 'byte $index');
          }
        },
      );

      expect(payload, List<int>.generate(256, (index) => index));
    });

    test('supports empty input with a non-null allocation', () {
      final result = AuraSecureMem.processSecureData<int>(
        rawData: Uint8List(0),
        action: (pointer, length) {
          expect(pointer, isNot(nullptr));
          expect(length, 0);
          return length;
        },
      );

      expect(result, 0);
    });

    test('rethrows action errors', () {
      expect(
        () => AuraSecureMem.processSecureData<void>(
          rawData: Uint8List.fromList([1]),
          action: (pointer, length) => throw StateError('action failed'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects asynchronous actions to avoid use-after-free', () {
      expect(
        () => AuraSecureMem.processSecureData<Future<void>>(
          rawData: Uint8List.fromList([1, 2, 3]),
          action: (pointer, length) async {
            expect(pointer, isNot(nullptr));
            expect(length, 3);
          },
        ),
        throwsArgumentError,
      );
    });
  });
}
