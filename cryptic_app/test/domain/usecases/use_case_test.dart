// Test for domain use cases

import 'package:cryptic_app/domain/usecases/use_case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UseCaseResult', () {
    group('UseCaseSuccess', () {
      test('should store value', () {
        const result = UseCaseSuccess<int>(42);
        expect(result.value, equals(42));
      });

      test('isSuccess should return true', () {
        const result = UseCaseSuccess<String>('test');
        expect(result.isSuccess, isTrue);
        expect(result.isError, isFalse);
      });

      test('map should transform value', () {
        const result = UseCaseSuccess<int>(10);
        final mapped = result.map((v) => v * 2);

        expect(mapped, isA<UseCaseSuccess<int>>());
        expect((mapped as UseCaseSuccess<int>).value, equals(20));
      });

      test('fold should call onSuccess', () {
        const result = UseCaseSuccess<String>('hello');
        final folded = result.fold(
          onSuccess: (v) => 'success: $v',
          onError: (e, _) => 'error: $e',
        );

        expect(folded, equals('success: hello'));
      });

      test('equality should work correctly', () {
        const result1 = UseCaseSuccess<int>(42);
        const result2 = UseCaseSuccess<int>(42);
        const result3 = UseCaseSuccess<int>(43);

        expect(result1, equals(result2));
        expect(result1, isNot(equals(result3)));
      });

      test('toString should include value', () {
        const result = UseCaseSuccess<int>(42);
        expect(result.toString(), equals('UseCaseSuccess(42)'));
      });
    });

    group('UseCaseError', () {
      test('should store message', () {
        const result = UseCaseError<int>('Something went wrong');
        expect(result.message, equals('Something went wrong'));
      });

      test('should store exception', () {
        final exception = Exception('test');
        final result = UseCaseError<int>('error', exception);
        expect(result.exception, equals(exception));
      });

      test('exception can be null', () {
        const result = UseCaseError<int>('error');
        expect(result.exception, isNull);
      });

      test('isError should return true', () {
        const result = UseCaseError<String>('error');
        expect(result.isError, isTrue);
        expect(result.isSuccess, isFalse);
      });

      test('map should preserve error', () {
        const result = UseCaseError<int>('error message');
        final mapped = result.map((v) => v * 2);

        expect(mapped, isA<UseCaseError<int>>());
        expect((mapped as UseCaseError<int>).message, equals('error message'));
      });

      test('fold should call onError', () {
        const result = UseCaseError<String>('something failed');
        final folded = result.fold(
          onSuccess: (v) => 'success: $v',
          onError: (e, _) => 'error: $e',
        );

        expect(folded, equals('error: something failed'));
      });

      test('fold should pass exception to onError', () {
        final exception = Exception('inner');
        final result = UseCaseError<String>('outer', exception);
        Object? passedException;

        result.fold(
          onSuccess: (_) {},
          onError: (_, ex) {
            passedException = ex;
          },
        );

        expect(passedException, equals(exception));
      });

      test('equality should work correctly', () {
        const result1 = UseCaseError<int>('error');
        const result2 = UseCaseError<int>('error');
        const result3 = UseCaseError<int>('different error');

        expect(result1, equals(result2));
        expect(result1, isNot(equals(result3)));
      });

      test('toString should include message', () {
        const result = UseCaseError<int>('test error');
        expect(result.toString(), equals('UseCaseError(test error)'));
      });
    });
  });
}
