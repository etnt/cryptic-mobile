import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cryptic_app/data/crypto/ratchet/double_ratchet.dart';
import 'package:cryptic_app/data/crypto/ratchet/ratchet_state.dart';
import 'package:cryptic_app/data/engine/session_manager.dart';
import 'package:cryptic_app/data/storage/repositories/session_repository.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

class MockDoubleRatchet extends Mock implements DoubleRatchet {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(32));
    registerFallbackValue((Uint8List(32), Uint8List(32)));
    registerFallbackValue(RatchetState(
      rootKey: Uint8List(32),
      sendChainKey: Uint8List(32),
      sendMessageNumber: 0,
      recvChainKey: Uint8List(32),
      recvMessageNumber: 0,
      prevRecvChainLength: 0,
      dhSelf: (Uint8List(32), Uint8List(32)),
      dhRatchetStep: 0,
      skippedKeys: {},
      sendingChainActive: false,
      receivingChainActive: false,
      createdAt: DateTime.now(),
    ),);
  });

  late MockSessionRepository mockSessionRepository;
  late MockDoubleRatchet mockDoubleRatchet;
  late SessionManager sessionManager;

  setUp(() {
    mockSessionRepository = MockSessionRepository();
    mockDoubleRatchet = MockDoubleRatchet();
    sessionManager = SessionManager(
      sessionRepository: mockSessionRepository,
      doubleRatchet: mockDoubleRatchet,
    );
  });

  RatchetState createMockState() => RatchetState(
      rootKey: Uint8List(32),
      sendChainKey: Uint8List(32),
      sendMessageNumber: 0,
      recvChainKey: Uint8List(32),
      recvMessageNumber: 0,
      prevRecvChainLength: 0,
      dhSelf: (Uint8List(32), Uint8List(32)),
      dhRemote: null,
      dhRatchetStep: 0,
      skippedKeys: {},
      sendingChainActive: false,
      receivingChainActive: false,
      createdAt: DateTime.now(),
    );

  group('SessionManager initialization', () {
    test('should start with no sessions', () {
      expect(sessionManager.peerUsernames, isEmpty);
    });

    test('hasSession should return false for unknown peer', () {
      expect(sessionManager.hasSession('unknown_peer'), isFalse);
    });
  });

  group('SessionManager createSessionAsInitiator', () {
    setUp(() async {
      await sessionManager.initialize('alice');
    });

    test('should create session and persist it', () async {
      final rootKey = Uint8List(32);
      final dhKeyPair = (Uint8List(32), Uint8List(32));
      final mockState = createMockState();

      when(
        () => mockDoubleRatchet.initSender(
          rootKey: any(named: 'rootKey'),
          dhKeyPair: any(named: 'dhKeyPair'),
        ),
      ).thenAnswer((_) async => mockState);

      when(
        () => mockSessionRepository.saveSession(
          peerUsername: any(named: 'peerUsername'),
          state: any(named: 'state'),
        ),
      ).thenAnswer((_) async {});

      await sessionManager.createSessionAsInitiator(
        peerUsername: 'bob',
        sharedSecret: rootKey,
        ourDhKeyPair: dhKeyPair,
      );

      expect(sessionManager.hasSession('bob'), isTrue);
      verify(
        () => mockDoubleRatchet.initSender(
          rootKey: any(named: 'rootKey'),
          dhKeyPair: any(named: 'dhKeyPair'),
        ),
      ).called(1);
      verify(
        () => mockSessionRepository.saveSession(
          peerUsername: 'bob',
          state: any(named: 'state'),
        ),
      ).called(1);
    });

    test('hasSession should return true after session is created', () async {
      final rootKey = Uint8List(32);
      final dhKeyPair = (Uint8List(32), Uint8List(32));
      final mockState = createMockState();

      when(
        () => mockDoubleRatchet.initSender(
          rootKey: any(named: 'rootKey'),
          dhKeyPair: any(named: 'dhKeyPair'),
        ),
      ).thenAnswer((_) async => mockState);

      when(
        () => mockSessionRepository.saveSession(
          peerUsername: any(named: 'peerUsername'),
          state: any(named: 'state'),
        ),
      ).thenAnswer((_) async {});

      await sessionManager.createSessionAsInitiator(
        peerUsername: 'bob',
        sharedSecret: rootKey,
        ourDhKeyPair: dhKeyPair,
      );

      expect(sessionManager.hasSession('bob'), isTrue);
      expect(sessionManager.peerUsernames, contains('bob'));
    });
  });

  group('SessionManager createSessionAsResponder', () {
    setUp(() async {
      await sessionManager.initialize('bob');
    });

    test('should create session with remote public key', () async {
      final rootKey = Uint8List(32);
      final dhKeyPair = (Uint8List(32), Uint8List(32));
      final remotePublic = Uint8List.fromList(List.filled(32, 1));
      final mockState = createMockState();

      when(
        () => mockDoubleRatchet.initReceiver(
          rootKey: any(named: 'rootKey'),
          dhKeyPair: any(named: 'dhKeyPair'),
        ),
      ).thenAnswer((_) async => mockState);

      when(
        () => mockSessionRepository.saveSession(
          peerUsername: any(named: 'peerUsername'),
          state: any(named: 'state'),
        ),
      ).thenAnswer((_) async {});

      await sessionManager.createSessionAsResponder(
        peerUsername: 'alice',
        sharedSecret: rootKey,
        ourDhKeyPair: dhKeyPair,
        theirDhPublic: remotePublic,
      );

      expect(sessionManager.hasSession('alice'), isTrue);
      verify(
        () => mockDoubleRatchet.initReceiver(
          rootKey: any(named: 'rootKey'),
          dhKeyPair: any(named: 'dhKeyPair'),
        ),
      ).called(1);
    });
  });

  group('SessionManager loadSession', () {
    setUp(() async {
      await sessionManager.initialize('alice');
    });

    test('should load session from repository', () async {
      final mockState = createMockState();

      when(() => mockSessionRepository.loadSession(peerUsername: 'dave'))
          .thenAnswer((_) async => mockState);

      final result = await sessionManager.loadSession('dave');

      expect(result, isNotNull);
      expect(sessionManager.hasSession('dave'), isTrue);
    });

    test('should return null if session not found', () async {
      when(() => mockSessionRepository.loadSession(peerUsername: 'unknown'))
          .thenAnswer((_) async => null);

      final result = await sessionManager.loadSession('unknown');

      expect(result, isNull);
      expect(sessionManager.hasSession('unknown'), isFalse);
    });

    test('should use cached session if already loaded', () async {
      final mockState = createMockState();

      when(() => mockSessionRepository.loadSession(peerUsername: 'cached'))
          .thenAnswer((_) async => mockState);

      // Load first time
      await sessionManager.loadSession('cached');

      // Load second time - should use cache
      final result = await sessionManager.loadSession('cached');

      expect(result, isNotNull);
      // Should only call repository once
      verify(() => mockSessionRepository.loadSession(peerUsername: 'cached'))
          .called(1);
    });
  });

  group('SessionManager getSessionInfo', () {
    setUp(() async {
      await sessionManager.initialize('alice');
    });

    test('should return null for unknown peer', () {
      expect(sessionManager.getSessionInfo('unknown'), isNull);
    });

    test('should return session info for existing session', () async {
      final mockState = createMockState();

      when(
        () => mockDoubleRatchet.initSender(
          rootKey: any(named: 'rootKey'),
          dhKeyPair: any(named: 'dhKeyPair'),
        ),
      ).thenAnswer((_) async => mockState);

      when(
        () => mockSessionRepository.saveSession(
          peerUsername: any(named: 'peerUsername'),
          state: any(named: 'state'),
        ),
      ).thenAnswer((_) async {});

      await sessionManager.createSessionAsInitiator(
        peerUsername: 'eve',
        sharedSecret: Uint8List(32),
        ourDhKeyPair: (Uint8List(32), Uint8List(32)),
      );

      final info = sessionManager.getSessionInfo('eve');

      expect(info, isNotNull);
      expect(info!.peerUsername, 'eve');
      expect(info.hasSession, isTrue);
    });
  });

  group('SessionManager deleteSession', () {
    setUp(() async {
      await sessionManager.initialize('alice');
    });

    test('should remove session from cache and storage', () async {
      final mockState = createMockState();

      when(
        () => mockDoubleRatchet.initSender(
          rootKey: any(named: 'rootKey'),
          dhKeyPair: any(named: 'dhKeyPair'),
        ),
      ).thenAnswer((_) async => mockState);

      when(
        () => mockSessionRepository.saveSession(
          peerUsername: any(named: 'peerUsername'),
          state: any(named: 'state'),
        ),
      ).thenAnswer((_) async {});

      when(() => mockSessionRepository.deleteSession(peerUsername: 'frank'))
          .thenAnswer((_) async {});

      await sessionManager.createSessionAsInitiator(
        peerUsername: 'frank',
        sharedSecret: Uint8List(32),
        ourDhKeyPair: (Uint8List(32), Uint8List(32)),
      );

      expect(sessionManager.hasSession('frank'), isTrue);

      await sessionManager.deleteSession('frank');

      expect(sessionManager.hasSession('frank'), isFalse);
      verify(() => mockSessionRepository.deleteSession(peerUsername: 'frank'))
          .called(1);
    });
  });

  group('SessionManager getAllSessionInfos', () {
    setUp(() async {
      await sessionManager.initialize('alice');
    });

    test('should return empty map when no sessions', () {
      final infos = sessionManager.getAllSessionInfos();
      expect(infos, isEmpty);
    });

    test('should return all session infos', () async {
      final mockState = createMockState();

      when(
        () => mockDoubleRatchet.initSender(
          rootKey: any(named: 'rootKey'),
          dhKeyPair: any(named: 'dhKeyPair'),
        ),
      ).thenAnswer((_) async => mockState);

      when(
        () => mockSessionRepository.saveSession(
          peerUsername: any(named: 'peerUsername'),
          state: any(named: 'state'),
        ),
      ).thenAnswer((_) async {});

      await sessionManager.createSessionAsInitiator(
        peerUsername: 'bob',
        sharedSecret: Uint8List(32),
        ourDhKeyPair: (Uint8List(32), Uint8List(32)),
      );

      await sessionManager.createSessionAsInitiator(
        peerUsername: 'charlie',
        sharedSecret: Uint8List(32),
        ourDhKeyPair: (Uint8List(32), Uint8List(32)),
      );

      final infos = sessionManager.getAllSessionInfos();

      expect(infos, hasLength(2));
      expect(infos.containsKey('bob'), isTrue);
      expect(infos.containsKey('charlie'), isTrue);
    });
  });

  group('SessionManager dispose', () {
    test('should clear all sessions', () async {
      await sessionManager.initialize('alice');

      final mockState = createMockState();

      when(
        () => mockDoubleRatchet.initSender(
          rootKey: any(named: 'rootKey'),
          dhKeyPair: any(named: 'dhKeyPair'),
        ),
      ).thenAnswer((_) async => mockState);

      when(
        () => mockSessionRepository.saveSession(
          peerUsername: any(named: 'peerUsername'),
          state: any(named: 'state'),
        ),
      ).thenAnswer((_) async {});

      await sessionManager.createSessionAsInitiator(
        peerUsername: 'bob',
        sharedSecret: Uint8List(32),
        ourDhKeyPair: (Uint8List(32), Uint8List(32)),
      );

      expect(sessionManager.hasSession('bob'), isTrue);

      sessionManager.dispose();

      expect(sessionManager.peerUsernames, isEmpty);
    });
  });
}
