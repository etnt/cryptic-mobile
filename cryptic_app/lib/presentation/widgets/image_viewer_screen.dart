import 'dart:io';

import 'package:flutter/material.dart';

class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({required this.path, super.key});

  final String path;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: InteractiveViewer(
            child: Image.file(
              File(path),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white,
                size: 64,
              ),
            ),
          ),
        ),
      );
}
