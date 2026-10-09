import 'package:cryptic_app/data/storage/message_database.dart';
import 'package:cryptic_app/data/storage/repositories/message_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMessageDatabase extends Mock implements MessageDatabase {}

void main() {
  late MockMessageDatabase database;
  late MessageRepository repository;

  setUpAll(() {
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    database = MockMessageDatabase();
    repository = MessageRepository(database: database);
    when(() => database.isOpen).thenReturn(true);
  });

  test('getRecentMediaPaths queries the 30-day media window', () async {
    when(() => database.getRecentMediaPaths(since: any(named: 'since')))
        .thenAnswer((_) async => {'/media/recent.jpg'});

    final paths = await repository.getRecentMediaPaths();

    expect(paths, {'/media/recent.jpg'});
    final captured = verify(
      () => database.getRecentMediaPaths(since: captureAny(named: 'since')),
    ).captured.single as DateTime;
    final age = DateTime.now().difference(captured);
    expect(
      age.inMilliseconds,
      closeTo(
        const Duration(days: 30).inMilliseconds,
        const Duration(seconds: 2).inMilliseconds,
      ),
    );
  });

  test('clearLocalPaths delegates all removed file paths', () async {
    when(() => database.clearLocalPaths(any())).thenAnswer((_) async {});
    final paths = ['/media/one.jpg', '/media/two.pdf'];

    await repository.clearLocalPaths(paths);

    verify(() => database.clearLocalPaths(paths)).called(1);
  });
}
