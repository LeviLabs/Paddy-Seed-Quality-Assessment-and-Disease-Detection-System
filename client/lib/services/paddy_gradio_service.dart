import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;

/// Secure Cloudflare gateway for Hugging Face ViT inference.
/// Never store a Hugging Face secret token inside Flutter.
class PaddyGradioService {
  PaddyGradioService._();

  static const String gatewayUrl =
      'https://paddy-vit-api.levi000000007.workers.dev';

  static Future<Map<String, dynamic>> predict(File imageFile) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw StateError('Please sign in before analyzing paddy.');
    }

    // Force a fresh Firebase ID token.
    final tokenResult = await user.getIdTokenResult(true);
    final firebaseToken = tokenResult.token;

    if (firebaseToken == null || firebaseToken.isEmpty) {
      throw StateError('Could not obtain a Firebase ID token. Sign in again.');
    }

    // Log non-secret claims for troubleshooting.
    final claims = tokenResult.claims ?? <String, dynamic>{};

    final projectId = claims['aud']?.toString() ?? 'missing';

    final issuer = claims['iss']?.toString() ?? 'missing';

    debugPrint('Paddy Firebase token audience (project): $projectId');

    debugPrint('Paddy Firebase token issuer: $issuer');

    debugPrint('Firebase user ID present: ${user.uid.isNotEmpty}');

    final base = gatewayUrl.replaceFirst(RegExp(r'/+$'), '');

    final client = http.Client();

    try {
      // --------------------------------------------------
      // STEP 1: COMPRESS IMAGE
      // --------------------------------------------------

      Uint8List bytes;

      try {
        bytes =
            await FlutterImageCompress.compressWithFile(
              imageFile.absolute.path,
              minWidth: 800,
              minHeight: 800,
              quality: 80,
              format: CompressFormat.jpeg,
            ) ??
            await imageFile.readAsBytes();
      } catch (_) {
        bytes = await imageFile.readAsBytes();
      }

      if (bytes.isEmpty) {
        throw StateError('Selected paddy image is empty.');
      }

      // --------------------------------------------------
      // STEP 2: UPLOAD IMAGE THROUGH CLOUDFLARE
      // --------------------------------------------------

      final upload = http.MultipartRequest(
        'POST',
        Uri.parse('$base/gradio_api/upload'),
      );

      upload.headers['Authorization'] = 'Bearer $firebaseToken';

      upload.files.add(
        http.MultipartFile.fromBytes('files', bytes, filename: 'paddy.jpg'),
      );

      final uploaded = await client
          .send(upload)
          .timeout(const Duration(seconds: 120));

      final uploadResponse = await http.Response.fromStream(uploaded);

      _check(uploadResponse, 'Image upload', projectId: projectId);

      final paths = jsonDecode(uploadResponse.body);

      if (paths is! List || paths.isEmpty || paths.first is! String) {
        throw const FormatException('Unexpected Gradio image upload response.');
      }

      final uploadedPath = paths.first as String;

      // --------------------------------------------------
      // STEP 3: SUBMIT VIT PREDICTION
      // --------------------------------------------------

      final submitted = await client
          .post(
            Uri.parse('$base/gradio_api/call/predict'),
            headers: {
              'Authorization': 'Bearer $firebaseToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'data': [
                {
                  'path': uploadedPath,
                  'meta': {'_type': 'gradio.FileData'},
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));

      _check(submitted, 'Prediction submission', projectId: projectId);

      final submission = jsonDecode(submitted.body);

      if (submission is! Map || submission['event_id'] is! String) {
        throw const FormatException('Gradio did not return an event ID.');
      }

      final eventId = Uri.encodeComponent(submission['event_id'] as String);

      // --------------------------------------------------
      // STEP 4: RECEIVE STREAMED PREDICTION
      // --------------------------------------------------

      final eventRequest = http.Request(
        'GET',
        Uri.parse('$base/gradio_api/call/predict/$eventId'),
      );

      eventRequest.headers.addAll({
        'Authorization': 'Bearer $firebaseToken',
        'Accept': 'text/event-stream',
      });

      final eventResponse = await client
          .send(eventRequest)
          .timeout(const Duration(seconds: 90));

      if (eventResponse.statusCode < 200 || eventResponse.statusCode >= 300) {
        final body = await eventResponse.stream.bytesToString();

        _fail(eventResponse.statusCode, body, 'Prediction stream', projectId);
      }

      String? eventType;

      final dataLines = <String>[];

      final completion = Completer<Map<String, dynamic>>();

      void processEvent() {
        final type = eventType;
        final value = dataLines.join('\n');

        eventType = null;
        dataLines.clear();

        if (completion.isCompleted || value.isEmpty) {
          return;
        }

        try {
          if (type == 'complete') {
            final output = jsonDecode(value);

            if (output is! List || output.length < 2 || output[1] is! String) {
              throw const FormatException('Unexpected ViT prediction output.');
            }

            final result = jsonDecode(output[1] as String);

            if (result is! Map<String, dynamic>) {
              throw const FormatException('Invalid ViT prediction JSON.');
            }

            completion.complete(result);
          } else if (type == 'error') {
            if (value.toLowerCase().contains('quota')) {
              completion.completeError(
                StateError(
                  'Hugging Face ZeroGPU quota exceeded. '
                  'The Worker reached Hugging Face, '
                  'but inference was rejected.',
                ),
              );
            } else {
              completion.completeError(
                Exception('ViT inference failed: $value'),
              );
            }
          }
        } catch (error, stack) {
          if (!completion.isCompleted) {
            completion.completeError(error, stack);
          }
        }
      }

      final subscription = eventResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              if (line.isEmpty) {
                processEvent();
              } else if (line.startsWith('event:')) {
                eventType = line.substring(6).trim();
              } else if (line.startsWith('data:')) {
                dataLines.add(line.substring(5).trimLeft());
              }
            },
            onError: (Object error, StackTrace stack) {
              if (!completion.isCompleted) {
                completion.completeError(error, stack);
              }
            },
            onDone: () {
              processEvent();

              if (!completion.isCompleted) {
                completion.completeError(
                  const FormatException(
                    'Prediction stream closed unexpectedly.',
                  ),
                );
              }
            },
            cancelOnError: true,
          );

      try {
        return await completion.future.timeout(const Duration(minutes: 5));
      } finally {
        await subscription.cancel();
      }
    } finally {
      client.close();
    }
  }

  // --------------------------------------------------
  // HTTP RESPONSE CHECKING
  // --------------------------------------------------

  static void _check(
    http.Response response,
    String stage, {
    required String projectId,
  }) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _fail(response.statusCode, response.body, stage, projectId);
    }
  }

  static Never _fail(int status, String body, String stage, String projectId) {
    if (status == 401) {
      throw HttpException(
        '$stage failed (401): '
        'Firebase authentication was rejected by Cloudflare. '
        'App token project: $projectId. '
        'Confirm your Worker FIREBASE_PROJECT_ID matches '
        'and that the Worker correctly verifies Firebase '
        'ID token signatures. '
        'Worker response: $body',
      );
    }

    if (status == 403) {
      throw HttpException(
        '$stage failed (403): access denied. '
        'Check Worker permissions, Firebase authorization '
        'rules, and Hugging Face access. '
        'Response: $body',
      );
    }

    throw HttpException('$stage failed ($status): $body');
  }
}
