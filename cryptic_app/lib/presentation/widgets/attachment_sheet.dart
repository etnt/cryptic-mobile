import 'package:flutter/material.dart';

enum AttachmentSource { camera, gallery, file }

class AttachmentSheet extends StatelessWidget {
  const AttachmentSheet({required this.onSelected, super.key});

  final ValueChanged<AttachmentSource> onSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(title: Text('Attach')),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () => _select(context, AttachmentSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Gallery'),
              onTap: () => _select(context, AttachmentSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('File'),
              onTap: () => _select(context, AttachmentSource.file),
            ),
          ],
        ),
      );

  void _select(BuildContext context, AttachmentSource source) {
    Navigator.pop(context);
    onSelected(source);
  }
}
