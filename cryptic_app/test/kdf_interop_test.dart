// Cross-platform KDF interoperability test
//
// This test derives keys using the same inputs as the Erlang server
// and prints hex outputs for manual comparison.
//
// Run with: dart test test/kdf_interop_test.dart

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptic_app/data/crypto/primitives/kdf_service.dart';

void main() {
  final kdf = KdfService();

  // Use a well-known test key (all zeros, then all ones, etc.)
  final testRootKey = Uint8List(32);
  // Fill with a known pattern: 0x01, 0x02, ... 0x20
  for (var i = 0; i < 32; i++) {
    testRootKey[i] = i + 1;
  }

  test('KDF derive chain key with context "init"', () async {
    final result = await kdf.deriveKey(
      length: 32,
      subkeyId: 0,
      context: 'init',
      masterKey: testRootKey,
    );
    print('Input rootKey: ${_hex(testRootKey)}');
    print('KDF(32, 0, "init", rootKey) = ${_hex(result)}');
  });

  test('KDF derive chain key with context "resp"', () async {
    final result = await kdf.deriveKey(
      length: 32,
      subkeyId: 0,
      context: 'resp',
      masterKey: testRootKey,
    );
    print('KDF(32, 0, "resp", rootKey) = ${_hex(result)}');
  });

  test('KDF derive message key from chain key', () async {
    // First derive "init" chain key
    final chainKey = await kdf.deriveKey(
      length: 32,
      subkeyId: 0,
      context: 'init',
      masterKey: testRootKey,
    );
    print('chainKey(init): ${_hex(chainKey)}');

    // Then derive message key: kdf_derive(32, 0, "msg", chainKey)
    final messageKey = await kdf.deriveKey(
      length: 32,
      subkeyId: 0,
      context: 'msg',
      masterKey: chainKey,
    );
    print('messageKey = KDF(32, 0, "msg", chainKey): ${_hex(messageKey)}');

    // Then derive enc key: kdf_derive(32, 0, "enc", messageKey)
    final encKey = await kdf.deriveKey(
      length: 32,
      subkeyId: 0,
      context: 'enc',
      masterKey: messageKey,
    );
    print('encKey = KDF(32, 0, "enc", messageKey): ${_hex(encKey)}');
  });

  test('Full chain: rootKey -> chainKey(resp) -> messageKey -> encKey',
      () async {
    // Derive "resp" chain key (what Bob uses for sending, Alice for receiving)
    final chainKey = await kdf.deriveKey(
      length: 32,
      subkeyId: 0,
      context: 'resp',
      masterKey: testRootKey,
    );
    print('chainKey(resp): ${_hex(chainKey)}');

    // Derive message key for msg_number=0
    final messageKey = await kdf.deriveKey(
      length: 32,
      subkeyId: 0,
      context: 'msg',
      masterKey: chainKey,
    );
    print('messageKey(msg,0): ${_hex(messageKey)}');

    // Derive enc key
    final encKey = await kdf.deriveKey(
      length: 32,
      subkeyId: 0,
      context: 'enc',
      masterKey: messageKey,
    );
    print('encKey: ${_hex(encKey)}');
  });
}

String _hex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
