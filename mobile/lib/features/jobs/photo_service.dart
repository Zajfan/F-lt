import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../data/local_store.dart';

/// Copies picker-owned temporary files into app-owned durable storage.
/// The pending job binding also handles Android killing the activity mid-pick.
class PhotoService {
  PhotoService(this.store, {ImagePicker? picker})
    : picker = picker ?? ImagePicker();
  final LocalStore store;
  final ImagePicker picker;
  Future<void> _save(String jobId, XFile picked) async {
    final id = const Uuid().v4();
    final directory = Directory(
      path.join((await getApplicationDocumentsDirectory()).path, 'job-photos'),
    );
    await directory.create(recursive: true);
    final extension = path.extension(picked.path).toLowerCase();
    final target = File(
      path.join(directory.path, '$id${extension.isEmpty ? '.jpg' : extension}'),
    );
    await picked.saveTo(target.path);
    try {
      await store.addJobRecord('photo', {
        'id': id,
        'jobId': jobId,
        'path': target.path,
        'caption': '',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      await target.delete();
      rethrow;
    }
  }

  Future<void> pick(String jobId, ImageSource source) async {
    await store.put('capture', {
      'id': 'pending',
      'jobId': jobId,
      'pending': true,
    });
    try {
      final image = await picker.pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
      if (image != null) await _save(jobId, image);
    } finally {
      await store.put('capture', {'id': 'pending', 'pending': false});
    }
  }

  Future<void> recover() async {
    if (!Platform.isAndroid) return;
    final pending = await store.get('capture', 'pending');
    if (pending?['pending'] != true) return;
    final response = await picker.retrieveLostData();
    for (final file in response.files ?? <XFile>[]) {
      await _save(pending!['jobId'] as String, file);
    }
    await store.put('capture', {'id': 'pending', 'pending': false});
    if (response.exception != null) {
      throw StateError(
        'Bilden kunde inte återställas. Prova att lägga till den igen.',
      );
    }
  }
}
