/// Loading overlay widget.
///
/// Displays a semi-transparent overlay with loading indicator.
library;

import 'package:flutter/material.dart';

/// A loading overlay that covers the entire screen.
class LoadingOverlay extends StatelessWidget {
  /// Creates a loading overlay.
  const LoadingOverlay({
    super.key,
    this.message,
    this.isLoading = true,
    this.child,
  });

  /// Optional loading message.
  final String? message;

  /// Whether to show the loading overlay.
  final bool isLoading;

  /// Child widget to display behind the overlay.
  final Widget? child;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          if (child != null) child!,
          if (isLoading)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  margin: const EdgeInsets.all(32),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        if (message != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            message!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}

/// Extension to easily show loading overlay.
extension LoadingOverlayExtension on BuildContext {
  /// Show a loading overlay dialog.
  Future<void> showLoadingOverlay({String? message}) => showDialog(
        context: this,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: Center(
            child: Card(
              margin: const EdgeInsets.all(32),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (message != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
