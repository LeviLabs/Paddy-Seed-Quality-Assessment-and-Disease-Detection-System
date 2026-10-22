import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Access to the private paddy-images bucket using Firebase JWT authentication.
class PaddyStorageService {
  PaddyStorageService._();
  static const bucket = 'paddy-images';

  static Future<String> uploadImage({
    required File file,
    required String testType,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in before uploading images.');
    // Firebase Admin custom claims may require refreshing a token after setup.
    final token = await user.getIdTokenResult(true);
    if (token.claims?['role'] != 'authenticated') {
      throw StateError(
        'Firebase user is missing the authenticated role claim.',
      );
    }
    final ext = file.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw StateError('Image exceeds the 5 MB Supabase bucket limit.');
    }
    final path =
        'users/${user.uid}/$testType/${DateTime.now().microsecondsSinceEpoch}.$ext';
    await Supabase.instance.client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mime, upsert: false),
        );
    return path;
  }

  static Future<String> signedImageUrl(String path) async {
    if (path.isEmpty) return '';
    return Supabase.instance.client.storage
        .from(bucket)
        .createSignedUrl(path, 3600);
  }
}
