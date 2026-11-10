import 'dart:io';

/// Keeps image references local to the device for now.
abstract final class StorageService {
  static Future<String> uploadImage(File file, {String? folder}) async {
    return file.path;
  }

  static Future<List<String>> uploadImages(
    List<File> files, {
    String? folder,
  }) async {
    final urls = <String>[];
    for (final file in files) {
      urls.add(await uploadImage(file, folder: folder));
    }
    return urls;
  }
}
