/// Base use case interface.
///
/// Use cases encapsulate business logic and orchestrate data operations.
/// They are called by the presentation layer and delegate to repositories
/// and services.
library;

/// Base interface for use cases with input and output types.
///
/// Type Parameters:
/// - [Input]: The input type for the use case
/// - [Output]: The output type for the use case
abstract class UseCase<Input, Output> {
  /// Execute the use case with the given [input].
  Future<UseCaseResult<Output>> call(Input input);
}

/// Use case without input parameters.
abstract class NoInputUseCase<Output> {
  /// Execute the use case.
  Future<UseCaseResult<Output>> call();
}

/// Use case result wrapper.
///
/// Provides a consistent way to handle success and error cases.
sealed class UseCaseResult<T> {
  const UseCaseResult();

  /// Returns true if the result is successful.
  bool get isSuccess => this is UseCaseSuccess<T>;

  /// Returns true if the result is an error.
  bool get isError => this is UseCaseError<T>;

  /// Maps the result to a new type.
  UseCaseResult<R> map<R>(R Function(T value) mapper);

  /// Folds the result into a single value.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(String error, Object? exception) onError,
  });
}

/// Successful use case result.
class UseCaseSuccess<T> extends UseCaseResult<T> {
  /// Creates a success result with the given [value].
  const UseCaseSuccess(this.value);

  /// The successful result value.
  final T value;

  @override
  UseCaseResult<R> map<R>(R Function(T value) mapper) => UseCaseSuccess(mapper(value));

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(String error, Object? exception) onError,
  }) => onSuccess(value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UseCaseSuccess<T> &&
          runtimeType == other.runtimeType &&
          value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'UseCaseSuccess($value)';
}

/// Failed use case result.
class UseCaseError<T> extends UseCaseResult<T> {
  /// Creates an error result with the given [message] and optional [exception].
  const UseCaseError(this.message, [this.exception]);

  /// Error message describing what went wrong.
  final String message;

  /// Optional exception that caused the error.
  final Object? exception;

  @override
  UseCaseResult<R> map<R>(R Function(T value) mapper) => UseCaseError(message, exception);

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(String error, Object? exception) onError,
  }) => onError(message, exception);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UseCaseError<T> &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'UseCaseError($message)';
}
