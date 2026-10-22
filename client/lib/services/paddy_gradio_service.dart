import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;

/// Calls a secure Cloudflare Worker which validates Firebase login and
/// supplies the private Hugging Face token. NEVER store HF_TOKEN in Flutter.
class PaddyGradioService {
  PaddyGradioService._();

  // Replace ONLY this value with your deployed Cloudflare Workers URL.
  static const String gatewayUrl =
      'https://paddy-vit-api.levi000000007.workers.dev';

  static Future<Map<String, dynamic>> predict(File imageFile) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Please sign in before analyzing paddy.');
    }
    final firebaseToken = await user.getIdToken();
    if (firebaseToken == null || firebaseToken.isEmpty) {
      throw StateError('Could not obtain Firebase sign-in token.');
    }
    if (gatewayUrl.contains('YOUR-WORKER')) {
      throw StateError('Set PaddyGradioService.gatewayUrl first.');
    }

    final base = gatewayUrl.replaceAll(RegExp(r'/$'), '');
    final client = http.Client();
    try {
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
      _check(uploadResponse, 'Image upload');
      final paths = jsonDecode(uploadResponse.body);
      if (paths is! List || paths.isEmpty || paths.first is! String) {
        throw const FormatException('Unexpected Gradio upload response');
      }

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
                  'path': paths.first,
                  'meta': {'_type': 'gradio.FileData'},
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));
      _check(submitted, 'Prediction submission');
      final submission = jsonDecode(submitted.body);
      if (submission is! Map || submission['event_id'] is! String) {
        throw const FormatException('Gradio did not return an event ID');
      }
      final eventId = Uri.encodeComponent(submission['event_id'] as String);
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
      if (eventResponse.statusCode != 200) {
        final body = await eventResponse.stream.bytesToString();
        throw HttpException(
          'Prediction stream error: '
          '${eventResponse.statusCode} $body',
        );
      }
      String? eventType;
      final dataLines = <String>[];
      final completion = Completer<Map<String, dynamic>>();
      void processEvent() {
        if (completion.isCompleted) return;
        final value = dataLines.join('\n');
        if (value.isEmpty) {
          eventType = null;
          dataLines.clear();
          return;
        }
        try {
          if (eventType == 'complete') {
            final output = jsonDecode(value);
            if (output is! List || output.length < 2 || output[1] is! String) {
              throw const FormatException('Unexpected ViT prediction data');
            }
            final result = jsonDecode(output[1] as String);
            if (result is! Map<String, dynamic>) {
              throw const FormatException('Invalid ViT prediction JSON');
            }
            completion.complete(result);
          } else if (eventType == 'error') {
            completion.completeError(Exception('ViT prediction error: $value'));
          }
        } catch (error, stack) {
          completion.completeError(error, stack);
        }
        eventType = null;
        dataLines.clear();
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
              if (!completion.isCompleted)
                completion.completeError(error, stack);
            },
            onDone: () {
              processEvent();
              if (!completion.isCompleted) {
                completion.completeError(
                  const FormatException(
                    'Prediction stream closed unexpectedly',
                  ),
                );
              }
            },
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

  static void _check(http.Response response, String stage) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        '$stage failed: '
        '${response.statusCode} ${response.body}',
      );
    }
  }
}
