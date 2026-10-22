import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../services/paddy_storage_service.dart';
import '../services/paddy_gradio_service.dart';

class InputPage {
  InputPage._();

  // ============================================================
  // RENDER API — TWO SEPARATE SERVICES
  // ============================================================

  /// Plant Disease Render Service URL
  /// Update this after creating the new Render service
  static const String plantDiseaseUrl =
      'https://paddy-plant-disease.onrender.com';

  /// Public Gradio Space (classification only).
  static const String paddyClassificationUrl =
      'https://levi7377-peddy.hf.space';

  // ============================================================
  // WARM UP BOTH SERVERS (RENDER COLD START MITIGATION)
  // ============================================================

  static void warmUpServer() {
    try {
      http
          .get(Uri.parse('$plantDiseaseUrl/health'))
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () => http.Response('', 408),
          )
          .catchError((_) => http.Response('', 500));
    } catch (_) {}
  }

  // ============================================================
  // SHOW CAMERA OPTIONS
  // ============================================================

  static void show(BuildContext context) {
    // Warm up the Render AI backend immediately
    warmUpServer();

    // This is the caller's (e.g. HomeScreen's) context. It stays
    // alive after the bottom sheet closes, so it's the one we use
    // for navigating to the result pages below.
    final BuildContext pageContext = context;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          decoration: const BoxDecoration(
            color: Color(0xFF4CAF7D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Text(
                'Choose Test',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                'Choose what you want to test',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.85),
                ),
              ),

              const SizedBox(height: 22),

              _cameraOptionTile(
                sheetContext: sheetContext,
                pageContext: pageContext,
                icon: Icons.coronavirus_rounded,
                title: 'Plant Disease',
                subtitle: 'Scan a leaf for disease detection',
                testType: 'plant_disease',
              ),

              const SizedBox(height: 14),

              _cameraOptionTile(
                sheetContext: sheetContext,
                pageContext: pageContext,
                icon: Icons.grass_rounded,
                title: 'Paddy Classification',
                subtitle: 'Scan paddy seeds for purity and quality',
                testType: 'paddy_classification',
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // CAMERA OPTION TILE
  // ============================================================

  static Widget _cameraOptionTile({
    required BuildContext sheetContext,
    required BuildContext pageContext,
    required IconData icon,
    required String title,
    required String subtitle,
    required String testType,
  }) {
    return GestureDetector(
      onTap: () {
        // Close the sheet using its own context...
        Navigator.pop(sheetContext);

        // ...but do the actual work (camera + navigation) using
        // the page's context, which stays alive after the sheet
        // is gone.
        _showImageSourceOptions(pageContext, testType);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF2E7D53)),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),

            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CHOOSE CAMERA OR GALLERY AFTER SELECTING A TEST
  // ============================================================

  static Future<void> _showImageSourceOptions(
    BuildContext context,
    String testType,
  ) async {
    if (!context.mounted) return;

    final String heading = testType == 'plant_disease'
        ? 'Plant Disease'
        : 'Paddy Classification';

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        decoration: const BoxDecoration(
          color: Color(0xFF4CAF7D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              heading,
              style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose how to add your image',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.85),
              ),
            ),
            const SizedBox(height: 22),
            _imageSourceTile(
              sheetContext: sheetContext,
              icon: Icons.camera_alt_rounded,
              title: 'Take Photo',
              subtitle: 'Open your camera',
              source: ImageSource.camera,
            ),
            const SizedBox(height: 14),
            _imageSourceTile(
              sheetContext: sheetContext,
              icon: Icons.photo_library_rounded,
              title: 'Upload from Gallery',
              subtitle: 'Choose an existing photo',
              source: ImageSource.gallery,
            ),
          ],
        ),
      ),
    );

    if (source == null || !context.mounted) return;
    await _pickImageForTest(context, testType, source);
  }

  static Widget _imageSourceTile({
    required BuildContext sheetContext,
    required IconData icon,
    required String title,
    required String subtitle,
    required ImageSource source,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(sheetContext, source),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: const Color(0xFF2E7D53)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }

  static Future<void> _pickImageForTest(
    BuildContext context,
    String testType,
    ImageSource source,
  ) async {
    final ImagePicker picker = ImagePicker();
    XFile? photo;

    try {
      photo = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 800,
        maxHeight: 800,
      );
    } catch (e) {
      debugPrint('Image selection error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not select an image: $e')),
        );
      }
      return;
    }

    if (photo == null || !context.mounted) return;

    final File imageFile = File(photo.path);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => testType == 'plant_disease'
            ? PlantDiseaseInputPage(imageFile: imageFile)
            : PaddyClassificationInputPage(imageFile: imageFile),
      ),
    );
  }
}

// ================================================================
// PLANT DISEASE INPUT PAGE
// ================================================================

class PlantDiseaseInputPage extends StatefulWidget {
  final File imageFile;

  const PlantDiseaseInputPage({super.key, required this.imageFile});

  @override
  State<PlantDiseaseInputPage> createState() => _PlantDiseaseInputPageState();
}

class _PlantDiseaseInputPageState extends State<PlantDiseaseInputPage> {
  bool _isRunning = false;
  String? _errorMessage;
  String _processingText = 'Preparing image...';
  double _progress = 0.0;
  Timer? _progressTimer;

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // SEND IMAGE TO RENDER
  // ============================================================

  Future<Map<String, dynamic>> _sendToRender() async {
    final Uri url = Uri.parse('${InputPage.plantDiseaseUrl}/predict');

    const int maxAttempts = 2;
    http.Response? response;

    // Compress image before sending (fixes large image 502 errors)
    Uint8List imageBytes;
    try {
      final Uint8List? compressed = await FlutterImageCompress.compressWithFile(
        widget.imageFile.absolute.path,
        minWidth: 800,
        minHeight: 800,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      imageBytes = compressed ?? await widget.imageFile.readAsBytes();
    } catch (_) {
      imageBytes = await widget.imageFile.readAsBytes();
    }

    debugPrint('Compressed image size: ${imageBytes.length ~/ 1024}KB');

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final http.MultipartRequest request = http.MultipartRequest(
          'POST',
          url,
        );

        request.files.add(
          http.MultipartFile.fromBytes(
            'image',
            imageBytes,
            filename: 'image.jpg',
          ),
        );

        final http.StreamedResponse streamedResponse = await request
            .send()
            .timeout(const Duration(seconds: 120));

        response = await http.Response.fromStream(streamedResponse);

        debugPrint(
          'Render attempt $attempt status: '
          '${response.statusCode}',
        );

        debugPrint(
          'Render response: '
          '${response.body}',
        );

        if (response.statusCode == 200) {
          break;
        }

        if ((response.statusCode == 502 ||
                response.statusCode == 503 ||
                response.statusCode == 504) &&
            attempt < maxAttempts) {
          debugPrint(
            'Render server returned '
            '${response.statusCode}. '
            'Retrying in ${attempt * 3} seconds...',
          );

          await Future.delayed(Duration(seconds: attempt * 3));
          continue;
        }

        throw Exception(
          'Server error '
          '${response.statusCode}: '
          '${response.body}',
        );
      } on TimeoutException {
        if (attempt == maxAttempts) {
          throw Exception('Request to AI server timed out after 120 seconds.');
        }

        debugPrint(
          'Render request timed out. '
          'Retrying in ${attempt * 3} seconds...',
        );

        await Future.delayed(Duration(seconds: attempt * 3));
      } on SocketException catch (e) {
        if (attempt == maxAttempts) {
          throw Exception('Could not connect to AI server: $e');
        }

        debugPrint(
          'Render connection error: $e. '
          'Retrying in ${attempt * 3} seconds...',
        );

        await Future.delayed(Duration(seconds: attempt * 3));
      }
    }

    final http.Response? finalResponse = response;
    if (finalResponse == null || finalResponse.statusCode != 200) {
      throw Exception('AI server did not return a successful response.');
    }

    final dynamic decoded = jsonDecode(finalResponse.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response from server');
    }

    return decoded;
  }

  // ============================================================
  // UPLOAD TO PRIVATE SUPABASE STORAGE
  // ============================================================

  Future<String> _uploadToSupabaseStorage() async {
    return PaddyStorageService.uploadImage(
      file: widget.imageFile,
      testType: 'plant_disease',
    );
  }

  Future<void> _saveResultToFirestore({
    required Map<String, dynamic> result,
    required String imagePath,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Please sign in to save your scan history.');
    }
    final data = <String, dynamic>{
      'testType': 'plant_disease',
      'confidence': (result['confidence'] as num?)?.toDouble() ?? 0.0,
      'classIndex': result['class_index'],
      'predictions': result['predictions'] ?? <String, dynamic>{},
      'imagePath': imagePath,
      'imageBucket': PaddyStorageService.bucket,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': DateTime.now().toIso8601String(),
    };
    data['disease'] = result['disease']?.toString() ?? 'Unknown';
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('test_history')
        .add(data);
    debugPrint('History successfully saved to Firestore');
  }

  // ============================================================
  // RUN PLANT DISEASE TEST
  // ============================================================

  Future<void> _runPlantDiseaseTest() async {
    if (_isRunning) {
      return;
    }

    setState(() {
      _isRunning = true;
      _errorMessage = null;
      _processingText = 'Connecting to AI server...';
      _progress = 0.15;
    });

    _progressTimer?.cancel();
    int seconds = 0;
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      seconds++;
      setState(() {
        if (_progress < 0.85) {
          _progress += 0.05;
        }
        if (seconds == 2) {
          _processingText = 'Uploading leaf image...';
        } else if (seconds == 5) {
          _processingText = 'AI is analyzing your leaf...';
        } else if (seconds > 12) {
          _processingText = 'Waking up AI server, please wait...';
        }
      });
    });

    try {
      final Map<String, dynamic> result = await _sendToRender();

      _progressTimer?.cancel();

      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Prediction failed');
      }

      if (!mounted) return;

      setState(() {
        _processingText = 'Analysis complete!';
        _progress = 1.0;
      });

      // Save to private Supabase Storage and Firestore.
      // If saving fails, show the result but report the failure honestly.
      String imageUrl = '';
      try {
        final imagePath = await _uploadToSupabaseStorage();
        await _saveResultToFirestore(result: result, imagePath: imagePath);
        imageUrl = await PaddyStorageService.signedImageUrl(imagePath);
      } catch (err) {
        debugPrint('History save failed: $err');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Prediction worked, but history was not fully saved: $err',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      if (!mounted) return;

      // --------------------------------------------------------
      // SHOW RESULT IMMEDIATELY
      // --------------------------------------------------------

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PlantDiseaseResultPage(
            imageFile: widget.imageFile,
            result: result,
            imageUrl: imageUrl,
          ),
        ),
      );
    } catch (e) {
      _progressTimer?.cancel();
      debugPrint('Plant disease processing error: $e');

      if (!mounted) return;

      setState(() {
        _isRunning = false;
        _errorMessage = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Analysis failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  // ============================================================
  // PROCESSING VIEW
  // ============================================================

  Widget _processingView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),

      child: Column(
        children: [
          const SizedBox(
            width: 70,
            height: 70,
            child: CircularProgressIndicator(
              strokeWidth: 4.5,
              color: Color(0xFF4CAF7D),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Analyzing Plant',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            _processingText,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
          ),

          const SizedBox(height: 22),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),

            child: LinearProgressIndicator(
              minHeight: 8,
              value: _progress,
              backgroundColor: const Color(0xFFE8E8E8),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF4CAF7D),
              ),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            '${(_progress * 100).round()}%',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'Please keep the app open while we process your image.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3ED),

      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F3ED),
        elevation: 0,

        title: Text(
          'Plant Disease',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),

        iconTheme: const IconThemeData(color: Colors.black87),
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),

          child: _isRunning
              ? Center(child: SingleChildScrollView(child: _processingView()))
              : Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),

                        child: Image.file(
                          widget.imageFile,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),

                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),

                    SizedBox(
                      width: double.infinity,

                      child: ElevatedButton(
                        onPressed: _runPlantDiseaseTest,

                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF7D),

                          padding: const EdgeInsets.symmetric(vertical: 16),

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),

                        child: Text(
                          'Analyze Plant Disease',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ================================================================
// PLANT DISEASE RESULT PAGE
// ================================================================

class PlantDiseaseResultPage extends StatelessWidget {
  final File imageFile;
  final Map<String, dynamic> result;
  final String imageUrl;

  const PlantDiseaseResultPage({
    super.key,
    required this.imageFile,
    required this.result,
    required this.imageUrl,
  });

  // ============================================================
  // FORMAT DISEASE NAME
  // ============================================================

  String _formatDisease(String disease) {
    return disease
        .split('_')
        .map(
          (String word) =>
              word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final String disease = result['disease']?.toString() ?? 'Unknown';

    final double confidence = result['confidence'] is num
        ? (result['confidence'] as num).toDouble()
        : 0.0;

    final String formattedDisease = _formatDisease(disease);

    final dynamic predictions = result['predictions'];

    return Scaffold(
      backgroundColor: const Color(0xFFF6F3ED),

      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F3ED),
        elevation: 0,

        title: Text(
          'Plant Disease Result',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),

        iconTheme: const IconThemeData(color: Colors.black87),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [
              // --------------------------------------------------
              // CAPTURED IMAGE
              // --------------------------------------------------
              ClipRRect(
                borderRadius: BorderRadius.circular(24),

                child: Image.file(
                  imageFile,
                  height: 300,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),

              const SizedBox(height: 20),

              // --------------------------------------------------
              // MAIN RESULT
              // --------------------------------------------------
              Container(
                padding: const EdgeInsets.all(20),

                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),

                child: Column(
                  children: [
                    const Icon(
                      Icons.local_florist_rounded,
                      size: 52,
                      color: Color(0xFF4CAF7D),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      formattedDisease,
                      textAlign: TextAlign.center,

                      style: GoogleFonts.poppins(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'Confidence',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      '${confidence.toStringAsFixed(2)}%',
                      style: GoogleFonts.poppins(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF4CAF7D),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // --------------------------------------------------
              // PREDICTION DETAILS
              // --------------------------------------------------
              if (predictions is Map)
                Container(
                  padding: const EdgeInsets.all(20),

                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      Text(
                        'Prediction Details',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),

                      const SizedBox(height: 14),

                      ...predictions.entries.map((entry) {
                        final String name = _formatDisease(
                          entry.key.toString(),
                        );

                        final double value = entry.value is num
                            ? (entry.value as num).toDouble()
                            : 0.0;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),

                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,

                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),

                              Text(
                                '${value.toStringAsFixed(2)}%',

                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // --------------------------------------------------
              // SAVED CONFIRMATION
              // --------------------------------------------------
              Container(
                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(18),
                ),

                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_done_rounded,
                      color: Color(0xFF2E7D53),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        'History is saved when you are signed in and storage is available.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: const Color(0xFF2E7D53),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // --------------------------------------------------
              // DONE
              // --------------------------------------------------
              SizedBox(
                width: double.infinity,

                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF7D),

                    padding: const EdgeInsets.symmetric(vertical: 16),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),

                  child: Text(
                    'Done',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================================================
// PADDY CLASSIFICATION INPUT PAGE
// ================================================================
// Mirrors PlantDiseaseInputPage: shows the captured photo, sends
// it to the render server, uploads it to Supabase, saves the
// result to Firestore, then opens the report page.

class PaddyClassificationInputPage extends StatefulWidget {
  final File imageFile;

  const PaddyClassificationInputPage({super.key, required this.imageFile});

  @override
  State<PaddyClassificationInputPage> createState() =>
      _PaddyClassificationInputPageState();
}

class _PaddyClassificationInputPageState
    extends State<PaddyClassificationInputPage> {
  bool _isRunning = false;
  String? _errorMessage;
  String _processingText = 'Preparing image...';
  double _progress = 0.0;
  Timer? _progressTimer;

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  // ============================================================
  // SEND IMAGE TO RENDER
  // ============================================================

  // ============================================================
  // SEND IMAGE TO HUGGING FACE GRADIO (upload -> queue -> SSE)
  // ============================================================

  Future<Map<String, dynamic>> _sendToHuggingFace() async {
    return PaddyGradioService.predict(widget.imageFile);
  }

  // ============================================================
  // UPLOAD TO PRIVATE SUPABASE STORAGE
  // ============================================================

  Future<String> _uploadToSupabaseStorage() async {
    return PaddyStorageService.uploadImage(
      file: widget.imageFile,
      testType: 'paddy_classification',
    );
  }

  Future<void> _saveResultToFirestore({
    required Map<String, dynamic> result,
    required String imagePath,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Please sign in to save your scan history.');
    }
    final data = <String, dynamic>{
      'testType': 'paddy_classification',
      'confidence': (result['confidence'] as num?)?.toDouble() ?? 0.0,
      'classIndex': result['class_index'],
      'predictions': result['all_predictions'] ?? <String, dynamic>{},
      'imagePath': imagePath,
      'imageBucket': PaddyStorageService.bucket,
      'createdAt': FieldValue.serverTimestamp(),
      'createdAtLocal': DateTime.now().toIso8601String(),
    };
    data['variety'] = result['variety']?.toString() ?? 'Unknown';
    if (result['grade'] != null) data['grade'] = result['grade'];
    if (result['moisture'] != null) data['moisture'] = result['moisture'];
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('test_history')
        .add(data);
    debugPrint('History successfully saved to Firestore');
  }

  // ============================================================
  // RUN PADDY CLASSIFICATION TEST
  // ============================================================

  Future<void> _runPaddyClassificationTest() async {
    if (_isRunning) {
      return;
    }

    setState(() {
      _isRunning = true;
      _errorMessage = null;
      _processingText = 'Connecting to AI server...';
      _progress = 0.15;
    });

    _progressTimer?.cancel();
    int seconds = 0;
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      seconds++;
      setState(() {
        if (_progress < 0.85) {
          _progress += 0.05;
        }
        if (seconds == 2) {
          _processingText = 'Uploading paddy image...';
        } else if (seconds == 5) {
          _processingText = 'AI is analyzing your sample...';
        } else if (seconds > 12) {
          _processingText = 'Waiting for Hugging Face GPU...';
        }
      });
    });

    try {
      final Map<String, dynamic> result = await _sendToHuggingFace();

      _progressTimer?.cancel();

      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Prediction failed');
      }

      if (!mounted) return;

      setState(() {
        _processingText = 'Analysis complete!';
        _progress = 1.0;
      });

      // Save to private Supabase Storage and Firestore.
      // If saving fails, show the result but report the failure honestly.
      String imageUrl = '';
      try {
        final imagePath = await _uploadToSupabaseStorage();
        await _saveResultToFirestore(result: result, imagePath: imagePath);
        imageUrl = await PaddyStorageService.signedImageUrl(imagePath);
      } catch (err) {
        debugPrint('History save failed: $err');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Prediction worked, but history was not fully saved: $err',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }

      if (!mounted) return;

      // --------------------------------------------------------
      // SHOW RESULT IMMEDIATELY
      // --------------------------------------------------------

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PaddyClassificationResultPage(
            imageFile: widget.imageFile,
            result: result,
            imageUrl: imageUrl,
          ),
        ),
      );
    } catch (e) {
      _progressTimer?.cancel();
      debugPrint('Paddy classification processing error: $e');

      if (!mounted) return;

      setState(() {
        _isRunning = false;
        _errorMessage = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Analysis failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  // ============================================================
  // PROCESSING VIEW
  // ============================================================

  Widget _processingView() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),

      child: Column(
        children: [
          const SizedBox(
            width: 70,
            height: 70,
            child: CircularProgressIndicator(
              strokeWidth: 4.5,
              color: Color(0xFF4CAF7D),
            ),
          ),

          const SizedBox(height: 24),

          Text(
            'Analyzing Paddy',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            _processingText,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.black54),
          ),

          const SizedBox(height: 22),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),

            child: LinearProgressIndicator(
              minHeight: 8,
              value: _progress,
              backgroundColor: const Color(0xFFE8E8E8),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF4CAF7D),
              ),
            ),
          ),

          const SizedBox(height: 8),

          Text(
            '${(_progress * 100).round()}%',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black54,
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'Please keep the app open while we process your image.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3ED),

      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F3ED),
        elevation: 0,

        title: Text(
          'Paddy Classification',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),

        iconTheme: const IconThemeData(color: Colors.black87),
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),

          child: _isRunning
              ? Center(child: SingleChildScrollView(child: _processingView()))
              : Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),

                        child: Image.file(
                          widget.imageFile,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),

                        child: Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),

                    SizedBox(
                      width: double.infinity,

                      child: ElevatedButton(
                        onPressed: _runPaddyClassificationTest,

                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF7D),

                          padding: const EdgeInsets.symmetric(vertical: 16),

                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),

                        child: Text(
                          'Analyze Paddy Sample',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ================================================================
// PADDY CLASSIFICATION RESULT PAGE
// ================================================================

class PaddyClassificationResultPage extends StatelessWidget {
  final File imageFile;
  final Map<String, dynamic> result;
  final String imageUrl;

  const PaddyClassificationResultPage({
    super.key,
    required this.imageFile,
    required this.result,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final String variety = result['variety']?.toString() ?? 'Unknown';

    final String grade = result['grade']?.toString() ?? 'Unknown';

    final double confidence = result['confidence'] is num
        ? (result['confidence'] as num).toDouble()
        : 0.0;

    final double? moisture = result['moisture'] is num
        ? (result['moisture'] as num).toDouble()
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F3ED),

      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F3ED),
        elevation: 0,

        title: Text(
          'Paddy Classification Result',
          style: GoogleFonts.poppins(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),

        iconTheme: const IconThemeData(color: Colors.black87),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,

            children: [
              // --------------------------------------------------
              // CAPTURED IMAGE
              // --------------------------------------------------
              ClipRRect(
                borderRadius: BorderRadius.circular(24),

                child: Image.file(
                  imageFile,
                  height: 300,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),

              const SizedBox(height: 20),

              // --------------------------------------------------
              // MAIN RESULT
              // --------------------------------------------------
              Container(
                padding: const EdgeInsets.all(20),

                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),

                child: Column(
                  children: [
                    const Icon(
                      Icons.grass_rounded,
                      size: 52,
                      color: Color(0xFF4CAF7D),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      variety,
                      textAlign: TextAlign.center,

                      style: GoogleFonts.poppins(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 10),

                    if (result['grade'] != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),

                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF7D).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),

                        child: Text(
                          'Grade $grade',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2E7D53),
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    Text(
                      'Confidence',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      '${confidence.toStringAsFixed(2)}%',
                      style: GoogleFonts.poppins(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF4CAF7D),
                      ),
                    ),

                    if (moisture != null) ...[
                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.water_drop_rounded,
                            size: 16,
                            color: Colors.blue,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${moisture.toStringAsFixed(1)}% Moisture',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // --------------------------------------------------
              // SAVED CONFIRMATION
              // --------------------------------------------------
              Container(
                padding: const EdgeInsets.all(16),

                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(18),
                ),

                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_done_rounded,
                      color: Color(0xFF2E7D53),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        'History is saved when you are signed in and storage is available.',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: const Color(0xFF2E7D53),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // --------------------------------------------------
              // DONE
              // --------------------------------------------------
              SizedBox(
                width: double.infinity,

                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF7D),

                    padding: const EdgeInsets.symmetric(vertical: 16),

                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),

                  child: Text(
                    'Done',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
