import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

class PickedPhoto {
  const PickedPhoto({required this.bytes, required this.filename});

  final Uint8List bytes;
  final String filename;
}

/// The server refuses anything larger, so the app checks first and says why.
const maxPhotoBytes = 2 * 1024 * 1024;

typedef PhotoPicker = Future<PickedPhoto?> Function(PhotoSource source);

/// Opens the camera or the gallery and returns a downsized photo (null = the user cancelled).
/// Behind a provider so tests can hand back fixed bytes without a platform channel.
final photoPickerProvider = Provider<PhotoPicker>((ref) {
  final picker = ImagePicker();
  return (source) async {
    final file = await picker.pickImage(
      source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
      // A product photo only needs to be recognisable on a phone screen; this keeps uploads small.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (file == null) return null;
    return PickedPhoto(bytes: await file.readAsBytes(), filename: file.name);
  };
});
