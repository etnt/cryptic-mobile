/// Get Users Use Case.
///
/// Handles requesting and retrieving the list of registered users.
library;

import '../../data/engine/cryptic_engine.dart';
import 'use_case.dart';

/// Result of user list request.
class GetUsersResult {
  /// Creates a get users result.
  const GetUsersResult({
    required this.users,
  });

  /// List of usernames.
  final List<String> users;
}

/// Use case for getting the list of registered users.
///
/// This use case:
/// 1. Requests the user list from the server
/// 2. Returns the current cached list
///
/// Note: The user list updates asynchronously. Subscribe to
/// engine events for real-time updates.
///
/// Example:
/// ```dart
/// final useCase = GetUsersUseCase(engine);
/// final result = await useCase();
///
/// result.fold(
///   onSuccess: (result) => print('Users: ${result.users}'),
///   onError: (error, _) => print('Failed: $error'),
/// );
/// ```
class GetUsersUseCase implements NoInputUseCase<GetUsersResult> {
  /// Creates a GetUsersUseCase.
  GetUsersUseCase(this._engine);

  final CrypticEngine _engine;

  @override
  Future<UseCaseResult<GetUsersResult>> call() async {
    try {
      // Check engine state
      if (!_engine.isInitialized) {
        return const UseCaseError('Engine not initialized');
      }
      if (!_engine.isConnected) {
        return const UseCaseError('Not connected to server');
      }

      // Request user list from server
      await _engine.requestUserList();

      // Return current cached list
      return UseCaseSuccess(GetUsersResult(
        users: _engine.state.users,
      ),);
    } catch (e) {
      return UseCaseError('Failed to get users', e);
    }
  }
}
