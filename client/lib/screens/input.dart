import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class InputPage {
  InputPage._();

  // ============================================================
  // RENDER API
  // ============================================================

  static const String renderBaseUrl =
      'https://paddy-seed-quality-assessment-and.onrender.com';

  // ============================================================
  // WARM UP SERVER (RENDER COLD START MITIGATION)
  // ============================================================

  static void warmUpServer() {
    try {
      http.get(Uri.parse('$renderBaseUrl/health')).timeout(
        const Duration(seconds: 15),
        onTimeout: () => http.Response('', 408),
      ).catchError((_) => http.Response('', 500));
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
          padding: const EdgeInsets.fromLTRB(
            20,
            24,
            20,
            32,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFF4CAF7D),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(
                    bottom: 20,
                  ),
                  decoration: BoxDecoration(
                    color:
                        Colors.white.withOpacity(0.5),
                    borderRadius:
                        BorderRadius.circular(2),
                  ),
                ),
              ),

              Text(
                'Camera',
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
                  color:
                      Colors.white.withOpacity(0.85),
                ),
              ),

              const SizedBox(height: 22),

              _cameraOptionTile(
                sheetContext: sheetContext,
                pageContext: pageContext,
                icon:
                    Icons.coronavirus_rounded,
                title: 'Plant Disease',
                subtitle:
                    'Scan a leaf for disease detection',
                testType: 'plant_disease',
              ),

              const SizedBox(height: 14),

              _cameraOptionTile(
                sheetContext: sheetContext,
                pageContext: pageContext,
                icon: Icons.grass_rounded,
                title: 'Paddy Classification',
                subtitle:
                    'Scan paddy seeds for purity and quality',
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
        _pickImageForTest(
          pageContext,
          testType,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              Colors.white.withOpacity(0.15),
          borderRadius:
              BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color:
                    const Color(0xFF2E7D53),
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 2),

                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white
                          .withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),

            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // OPEN PHONE CAMERA
  // ============================================================

  static Future<void> _pickImageForTest(
    BuildContext context,
    String testType,
  ) async {
    final ImagePicker picker =
        ImagePicker();

    XFile? photo;

    try {
      photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 800,
        maxHeight: 800,
      );
    } catch (e) {
      debugPrint(
        'Camera error: $e',
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open camera',
            ),
          ),
        );
      }

      return;
    }

    if (photo == null) {
      // User cancelled the camera — this is expected, just go
      // back quietly (already on the home screen since the sheet
      // is closed).
      return;
    }

    if (!context.mounted) {
      return;
    }

    final File imageFile =
        File(photo.path);

    if (testType == 'plant_disease') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              PlantDiseaseInputPage(
            imageFile: imageFile,
          ),
        ),
      );

      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PaddyClassificationInputPage(
          imageFile: imageFile,
        ),
      ),
    );
  }
}


// ================================================================
// PLANT DISEASE INPUT PAGE
// ================================================================

class PlantDiseaseInputPage
    extends StatefulWidget {
  final File imageFile;

  const PlantDiseaseInputPage({
    super.key,
    required this.imageFile,
  });

  @override
  State<PlantDiseaseInputPage> createState() =>
      _PlantDiseaseInputPageState();
}

class _PlantDiseaseInputPageState
    extends State<PlantDiseaseInputPage> {

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
    final Uri url = Uri.parse(
      '${InputPage.renderBaseUrl}/predict/plant-disease',
    );

    const int maxAttempts = 2;
    http.Response? response;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final http.MultipartRequest request = http.MultipartRequest(
          'POST',
          url,
        );

        request.files.add(
          await http.MultipartFile.fromPath(
            'image',
            widget.imageFile.path,
          ),
        );

        final http.StreamedResponse streamedResponse =
            await request.send().timeout(
          const Duration(seconds: 45),
        );

        response = await http.Response.fromStream(
          streamedResponse,
        );

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

          await Future.delayed(
            Duration(seconds: attempt * 3),
          );
          continue;
        }

        throw Exception(
          'Server error '
          '${response.statusCode}: '
          '${response.body}',
        );
      } on TimeoutException {
        if (attempt == maxAttempts) {
          throw Exception(
            'Request to AI server timed out after 120 seconds.',
          );
        }

        debugPrint(
          'Render request timed out. '
          'Retrying in ${attempt * 3} seconds...',
        );

        await Future.delayed(
          Duration(seconds: attempt * 3),
        );
      } on SocketException catch (e) {
        if (attempt == maxAttempts) {
          throw Exception(
            'Could not connect to AI server: $e',
          );
        }

        debugPrint(
          'Render connection error: $e. '
          'Retrying in ${attempt * 3} seconds...',
        );

        await Future.delayed(
          Duration(seconds: attempt * 3),
        );
      }
    }

    final http.Response? finalResponse = response;
    if (finalResponse == null || finalResponse.statusCode != 200) {
      throw Exception(
        'AI server did not return a successful response.',
      );
    }

    final dynamic decoded =
        jsonDecode(finalResponse.body);

    if (decoded
        is! Map<String, dynamic>) {
      throw Exception(
        'Invalid response from server',
      );
    }

    return decoded;
  }

  // ============================================================
  // UPLOAD TO FIREBASE STORAGE & ENCODE IMAGE
  // ============================================================

  Future<String> _uploadToFirebaseStorage() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      final String userId = user?.uid ?? 'guest_user';
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'plant_disease_$timestamp.jpg';

      final Reference ref = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(userId)
          .child('plant_disease')
          .child(fileName);

      final SettableMetadata metadata = SettableMetadata(
        contentType: 'image/jpeg',
      );

      final UploadTask uploadTask = ref.putFile(widget.imageFile, metadata);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('Firebase Storage URL: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('Firebase Storage upload warning: $e');
      return '';
    }
  }

  Future<String> _encodeImageToBase64() async {
    try {
      final Uint8List imageBytes = await widget.imageFile.readAsBytes();
      return base64Encode(imageBytes);
    } catch (e) {
      debugPrint('Image encoding error: $e');
      return '';
    }
  }

  // ============================================================
  // SAVE RESULT TO FIRESTORE (SAFE BACKGROUND)
  // ============================================================

  Future<void> _saveResultToFirestore({
    required Map<String, dynamic> result,
    required String imageUrl,
    required String imageBase64,
  }) async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('Firestore save skipped: user is not logged in.');
        return;
      }

      final String disease =
          result['disease']?.toString() ?? 'Unknown';

      final dynamic confidenceValue = result['confidence'];
      final double confidence = confidenceValue is num
          ? confidenceValue.toDouble()
          : 0.0;

      final dynamic predictionsValue = result['predictions'];
      final Map<String, dynamic> predictions = predictionsValue is Map
          ? Map<String, dynamic>.from(predictionsValue)
          : <String, dynamic>{};

      final int classIndex = result['class_index'] is num
          ? (result['class_index'] as num).toInt()
          : -1;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('test_history')
          .add({
        'testType': 'plant_disease',
        'disease': disease,
        'confidence': confidence,
        'classIndex': classIndex,
        'predictions': predictions,
        'imageUrl': imageUrl,
        'imageBase64': imageBase64,
        'localImagePath': widget.imageFile.path,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtLocal': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Firestore save skipped/failed: $e');
    }
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
        throw Exception(
          result['error'] ?? 'Prediction failed',
        );
      }

      if (!mounted) return;

      setState(() {
        _processingText = 'Analysis complete!';
        _progress = 1.0;
      });

      // Background safe storage & history save (non-blocking)
      String imageUrl = '';
      String imageBase64 = '';
      try {
        imageUrl = await _uploadToFirebaseStorage();
        imageBase64 = await _encodeImageToBase64();
        await _saveResultToFirestore(
          result: result,
          imageUrl: imageUrl,
          imageBase64: imageBase64,
        );
      } catch (err) {
        debugPrint('Non-critical background storage error: $err');
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
          content: Text(
            'Analysis failed: $e',
          ),
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
      padding:
          const EdgeInsets.all(24),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(24),
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

          const SizedBox(
            height: 24,
          ),

          Text(
            'Analyzing Plant',
            style:
                GoogleFonts.poppins(
              fontSize: 22,
              fontWeight:
                  FontWeight.bold,
              color:
                  Colors.black87,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          Text(
            _processingText,
            textAlign:
                TextAlign.center,
            style:
                GoogleFonts.poppins(
              fontSize: 14,
              color:
                  Colors.black54,
            ),
          ),

          const SizedBox(
            height: 22,
          ),

          ClipRRect(
            borderRadius:
                BorderRadius.circular(20),

            child:
                LinearProgressIndicator(
              minHeight: 8,
              value: _progress,
              backgroundColor:
                  const Color(
                0xFFE8E8E8,
              ),
              valueColor:
                  const AlwaysStoppedAnimation<
                      Color>(
                Color(0xFF4CAF7D),
              ),
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          Text(
            '${(_progress * 100).round()}%',
            style:
                GoogleFonts.poppins(
              fontSize: 12,
              fontWeight:
                  FontWeight.w600,
              color:
                  Colors.black54,
            ),
          ),

          const SizedBox(
            height: 20,
          ),

          Text(
            'Please keep the app open while we process your image.',
            textAlign:
                TextAlign.center,
            style:
                GoogleFonts.poppins(
              fontSize: 12,
              color:
                  Colors.black45,
            ),
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
      backgroundColor:
          const Color(0xFFF6F3ED),

      appBar: AppBar(
        backgroundColor:
            const Color(0xFFF6F3ED),
        elevation: 0,

        title: Text(
          'Plant Disease',
          style:
              GoogleFonts.poppins(
            color:
                Colors.black87,
            fontWeight:
                FontWeight.w600,
          ),
        ),

        iconTheme:
            const IconThemeData(
          color: Colors.black87,
        ),
      ),

      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.all(20),

          child:
              _isRunning
                  ? Center(
                      child:
                          SingleChildScrollView(
                        child:
                            _processingView(),
                      ),
                    )
                  : Column(
                      children: [

                        Expanded(
                          child:
                              ClipRRect(
                            borderRadius:
                                BorderRadius
                                    .circular(
                              24,
                            ),

                            child:
                                Image.file(
                              widget.imageFile,
                              width:
                                  double.infinity,
                              fit:
                                  BoxFit.cover,
                            ),
                          ),
                        ),

                        const SizedBox(
                          height: 20,
                        ),

                        if (_errorMessage !=
                            null)
                          Padding(
                            padding:
                                const EdgeInsets
                                    .only(
                              bottom: 12,
                            ),

                            child:
                                Text(
                              _errorMessage!,
                              textAlign:
                                  TextAlign.center,
                              style:
                                  const TextStyle(
                                color:
                                    Colors.red,
                                fontSize:
                                    12,
                              ),
                            ),
                          ),

                        SizedBox(
                          width:
                              double.infinity,

                          child:
                              ElevatedButton(
                            onPressed:
                                _runPlantDiseaseTest,

                            style:
                                ElevatedButton
                                    .styleFrom(
                              backgroundColor:
                                  const Color(
                                0xFF4CAF7D,
                              ),

                              padding:
                                  const EdgeInsets
                                      .symmetric(
                                vertical:
                                    16,
                              ),

                              shape:
                                  RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  16,
                                ),
                              ),
                            ),

                            child:
                                Text(
                              'Analyze Plant Disease',
                              style:
                                  GoogleFonts.poppins(
                                color:
                                    Colors.white,
                                fontWeight:
                                    FontWeight
                                        .w600,
                                fontSize:
                                    16,
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

class PlantDiseaseResultPage
    extends StatelessWidget {

  final File imageFile;
  final Map<String, dynamic>
      result;
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

  String _formatDisease(
    String disease,
  ) {
    return disease
        .split('_')
        .map(
          (String word) =>
              word.isEmpty
                  ? word
                  : word[0].toUpperCase() +
                      word.substring(1),
        )
        .join(' ');
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {

    final String disease =
        result['disease']
                ?.toString() ??
            'Unknown';

    final double confidence =
        result['confidence']
                is num
            ? (result['confidence']
                    as num)
                .toDouble()
            : 0.0;

    final String formattedDisease =
        _formatDisease(
      disease,
    );

    final dynamic predictions =
        result['predictions'];

    return Scaffold(
      backgroundColor:
          const Color(0xFFF6F3ED),

      appBar: AppBar(
        backgroundColor:
            const Color(0xFFF6F3ED),
        elevation: 0,

        title:
            Text(
          'Plant Disease Result',
          style:
              GoogleFonts.poppins(
            color:
                Colors.black87,
            fontWeight:
                FontWeight.w600,
          ),
        ),

        iconTheme:
            const IconThemeData(
          color: Colors.black87,
        ),
      ),

      body: SafeArea(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.all(
            20,
          ),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .stretch,

            children: [

              // --------------------------------------------------
              // CAPTURED IMAGE
              // --------------------------------------------------

              ClipRRect(
                borderRadius:
                    BorderRadius
                        .circular(24),

                child:
                    Image.file(
                  imageFile,
                  height: 300,
                  width:
                      double.infinity,
                  fit:
                      BoxFit.cover,
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              // --------------------------------------------------
              // MAIN RESULT
              // --------------------------------------------------

              Container(
                padding:
                    const EdgeInsets
                        .all(20),

                decoration:
                    BoxDecoration(
                  color:
                      Colors.white,
                  borderRadius:
                      BorderRadius
                          .circular(
                    24,
                  ),
                ),

                child: Column(
                  children: [

                    const Icon(
                      Icons
                          .local_florist_rounded,
                      size: 52,
                      color:
                          Color(
                        0xFF4CAF7D,
                      ),
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    Text(
                      formattedDisease,
                      textAlign:
                          TextAlign.center,

                      style:
                          GoogleFonts
                              .poppins(
                        fontSize: 25,
                        fontWeight:
                            FontWeight
                                .bold,
                        color:
                            Colors.black87,
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    Text(
                      'Confidence',
                      style:
                          GoogleFonts
                              .poppins(
                        fontSize: 14,
                        color:
                            Colors.black54,
                      ),
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      '${confidence.toStringAsFixed(2)}%',
                      style:
                          GoogleFonts
                              .poppins(
                        fontSize: 32,
                        fontWeight:
                            FontWeight
                                .bold,
                        color:
                            const Color(
                          0xFF4CAF7D,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              // --------------------------------------------------
              // PREDICTION DETAILS
              // --------------------------------------------------

              if (predictions is Map)
                Container(
                  padding:
                      const EdgeInsets
                          .all(20),

                  decoration:
                      BoxDecoration(
                    color:
                        Colors.white,
                    borderRadius:
                        BorderRadius
                            .circular(
                      24,
                    ),
                  ),

                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .start,

                    children: [

                      Text(
                        'Prediction Details',
                        style:
                            GoogleFonts
                                .poppins(
                          fontSize:
                              18,
                          fontWeight:
                              FontWeight
                                  .w600,
                          color:
                              Colors.black87,
                        ),
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      ...predictions
                          .entries
                          .map(
                        (entry) {

                          final String
                              name =
                              _formatDisease(
                            entry.key
                                .toString(),
                          );

                          final double
                              value =
                              entry.value
                                      is num
                                  ? (entry
                                          .value
                                      as num)
                                      .toDouble()
                                  : 0.0;

                          return Padding(
                            padding:
                                const EdgeInsets
                                    .only(
                              bottom:
                                  10,
                            ),

                            child:
                                Row(
                              children: [

                                Expanded(
                                  child:
                                      Text(
                                    name,

                                    style:
                                        GoogleFonts
                                            .poppins(
                                      fontSize:
                                          13,
                                      color:
                                          Colors.black87,
                                    ),
                                  ),
                                ),

                                Text(
                                  '${value.toStringAsFixed(2)}%',

                                  style:
                                      GoogleFonts
                                          .poppins(
                                    fontSize:
                                        13,
                                    fontWeight:
                                        FontWeight
                                            .w600,
                                    color:
                                        Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

              const SizedBox(
                height: 20,
              ),

              // --------------------------------------------------
              // SAVED CONFIRMATION
              // --------------------------------------------------

              Container(
                padding:
                    const EdgeInsets
                        .all(16),

                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xFFE8F5E9,
                  ),
                  borderRadius:
                      BorderRadius
                          .circular(
                    18,
                  ),
                ),

                child: Row(
                  children: [

                    const Icon(
                      Icons
                          .cloud_done_rounded,
                      color:
                          Color(
                        0xFF2E7D53,
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child:
                          Text(
                        'This result and image have been saved to your history.',
                        style:
                            GoogleFonts
                                .poppins(
                          fontSize:
                              12,
                          color:
                              const Color(
                            0xFF2E7D53,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              // --------------------------------------------------
              // DONE
              // --------------------------------------------------

              SizedBox(
                width:
                    double.infinity,

                child:
                    ElevatedButton(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pop();
                  },

                  style:
                      ElevatedButton
                          .styleFrom(
                    backgroundColor:
                        const Color(
                      0xFF4CAF7D,
                    ),

                    padding:
                        const EdgeInsets
                            .symmetric(
                      vertical: 16,
                    ),

                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        16,
                      ),
                    ),
                  ),

                  child:
                      Text(
                    'Done',
                    style:
                        GoogleFonts
                            .poppins(
                      color:
                          Colors.white,
                      fontWeight:
                          FontWeight
                              .w600,
                      fontSize:
                          16,
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

class PaddyClassificationInputPage
    extends StatefulWidget {
  final File imageFile;

  const PaddyClassificationInputPage({
    super.key,
    required this.imageFile,
  });

  @override
  State<PaddyClassificationInputPage>
      createState() =>
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

  Future<Map<String, dynamic>> _sendToRender() async {
    final Uri url = Uri.parse(
      '${InputPage.renderBaseUrl}/predict/paddy-classification',
    );

    const int maxAttempts = 2;
    http.Response? response;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final http.MultipartRequest request = http.MultipartRequest(
          'POST',
          url,
        );

        request.files.add(
          await http.MultipartFile.fromPath(
            'image',
            widget.imageFile.path,
          ),
        );

        final http.StreamedResponse streamedResponse =
            await request.send().timeout(
          const Duration(seconds: 45),
        );

        response = await http.Response.fromStream(
          streamedResponse,
        );

        debugPrint(
          'Render attempt $attempt status: ${response.statusCode}',
        );

        if (response.statusCode == 200) {
          break;
        }

        if ((response.statusCode == 502 ||
                response.statusCode == 503 ||
                response.statusCode == 504) &&
            attempt < maxAttempts) {
          debugPrint(
            'Render server returned ${response.statusCode}. Retrying in ${attempt * 3} seconds...',
          );

          await Future.delayed(
            Duration(seconds: attempt * 3),
          );
          continue;
        }

        throw Exception(
          'Server error ${response.statusCode}: ${response.body}',
        );
      } on TimeoutException {
        if (attempt == maxAttempts) {
          throw Exception(
            'Request to AI server timed out after 45 seconds.',
          );
        }

        debugPrint(
          'Render request timed out. Retrying in ${attempt * 3} seconds...',
        );

        await Future.delayed(
          Duration(seconds: attempt * 3),
        );
      } on SocketException catch (e) {
        if (attempt == maxAttempts) {
          throw Exception(
            'Could not connect to AI server: $e',
          );
        }

        debugPrint(
          'Render connection error: $e. Retrying in ${attempt * 3} seconds...',
        );

        await Future.delayed(
          Duration(seconds: attempt * 3),
        );
      }
    }

    final http.Response? finalResponse = response;
    if (finalResponse == null || finalResponse.statusCode != 200) {
      throw Exception(
        'AI server did not return a successful response.',
      );
    }

    final dynamic decoded = jsonDecode(finalResponse.body);

    if (decoded is! Map<String, dynamic>) {
      throw Exception(
        'Invalid response from server',
      );
    }

    return decoded;
  }

  // ============================================================
  // UPLOAD TO FIREBASE STORAGE & ENCODE IMAGE
  // ============================================================

  Future<String> _uploadToFirebaseStorage() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      final String userId = user?.uid ?? 'guest_user';
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileName = 'paddy_classification_$timestamp.jpg';

      final Reference ref = FirebaseStorage.instance
          .ref()
          .child('users')
          .child(userId)
          .child('paddy_classification')
          .child(fileName);

      final SettableMetadata metadata = SettableMetadata(
        contentType: 'image/jpeg',
      );

      final UploadTask uploadTask = ref.putFile(widget.imageFile, metadata);
      final TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint('Firebase Storage URL: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('Firebase Storage upload warning: $e');
      return '';
    }
  }

  Future<String> _encodeImageToBase64() async {
    try {
      final Uint8List imageBytes = await widget.imageFile.readAsBytes();
      return base64Encode(imageBytes);
    } catch (e) {
      debugPrint('Image encoding error: $e');
      return '';
    }
  }

  // ============================================================
  // SAVE RESULT TO FIRESTORE (SAFE BACKGROUND)
  // ============================================================

  Future<void> _saveResultToFirestore({
    required Map<String, dynamic> result,
    required String imageUrl,
    required String imageBase64,
  }) async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('Firestore save skipped: user is not logged in.');
        return;
      }

      final String variety =
          result['variety']?.toString() ?? 'Unknown';

      final String grade =
          result['grade']?.toString() ?? 'Unknown';

      final dynamic confidenceValue = result['confidence'];
      final double confidence = confidenceValue is num
          ? confidenceValue.toDouble()
          : 0.0;

      final dynamic moistureValue = result['moisture'];
      final double? moisture =
          moistureValue is num ? moistureValue.toDouble() : null;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('test_history')
          .add({
        'testType': 'paddy_classification',
        'variety': variety,
        'grade': grade,
        'confidence': confidence,
        'moisture': moisture,
        'imageUrl': imageUrl,
        'imageBase64': imageBase64,
        'localImagePath': widget.imageFile.path,
        'createdAt': FieldValue.serverTimestamp(),
        'createdAtLocal': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Firestore save skipped/failed: $e');
    }
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
          _processingText = 'Waking up AI server, please wait...';
        }
      });
    });

    try {
      final Map<String, dynamic> result = await _sendToRender();

      _progressTimer?.cancel();

      if (result['success'] != true) {
        throw Exception(
          result['error'] ?? 'Prediction failed',
        );
      }

      if (!mounted) return;

      setState(() {
        _processingText = 'Analysis complete!';
        _progress = 1.0;
      });

      // Background safe storage & history save (non-blocking)
      String imageUrl = '';
      String imageBase64 = '';
      try {
        imageUrl = await _uploadToFirebaseStorage();
        imageBase64 = await _encodeImageToBase64();
        await _saveResultToFirestore(
          result: result,
          imageUrl: imageUrl,
          imageBase64: imageBase64,
        );
      } catch (err) {
        debugPrint('Non-critical background storage error: $err');
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
          content: Text(
            'Analysis failed: $e',
          ),
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
      padding:
          const EdgeInsets.all(24),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(24),
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

          const SizedBox(
            height: 24,
          ),

          Text(
            'Analyzing Paddy',
            style:
                GoogleFonts.poppins(
              fontSize: 22,
              fontWeight:
                  FontWeight.bold,
              color:
                  Colors.black87,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          Text(
            _processingText,
            textAlign:
                TextAlign.center,
            style:
                GoogleFonts.poppins(
              fontSize: 14,
              color:
                  Colors.black54,
            ),
          ),

          const SizedBox(
            height: 22,
          ),

          ClipRRect(
            borderRadius:
                BorderRadius.circular(20),

            child:
                LinearProgressIndicator(
              minHeight: 8,
              value: _progress,
              backgroundColor:
                  const Color(
                0xFFE8E8E8,
              ),
              valueColor:
                  const AlwaysStoppedAnimation<
                      Color>(
                Color(0xFF4CAF7D),
              ),
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          Text(
            '${(_progress * 100).round()}%',
            style:
                GoogleFonts.poppins(
              fontSize: 12,
              fontWeight:
                  FontWeight.w600,
              color:
                  Colors.black54,
            ),
          ),

          const SizedBox(
            height: 20,
          ),

          Text(
            'Please keep the app open while we process your image.',
            textAlign:
                TextAlign.center,
            style:
                GoogleFonts.poppins(
              fontSize: 12,
              color:
                  Colors.black45,
            ),
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
      backgroundColor:
          const Color(0xFFF6F3ED),

      appBar: AppBar(
        backgroundColor:
            const Color(0xFFF6F3ED),
        elevation: 0,

        title: Text(
          'Paddy Classification',
          style:
              GoogleFonts.poppins(
            color:
                Colors.black87,
            fontWeight:
                FontWeight.w600,
          ),
        ),

        iconTheme:
            const IconThemeData(
          color: Colors.black87,
        ),
      ),

      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.all(20),

          child:
              _isRunning
                  ? Center(
                      child:
                          SingleChildScrollView(
                        child:
                            _processingView(),
                      ),
                    )
                  : Column(
                      children: [

                        Expanded(
                          child:
                              ClipRRect(
                            borderRadius:
                                BorderRadius
                                    .circular(
                              24,
                            ),

                            child:
                                Image.file(
                              widget.imageFile,
                              width:
                                  double.infinity,
                              fit:
                                  BoxFit.cover,
                            ),
                          ),
                        ),

                        const SizedBox(
                          height: 20,
                        ),

                        if (_errorMessage !=
                            null)
                          Padding(
                            padding:
                                const EdgeInsets
                                    .only(
                              bottom: 12,
                            ),

                            child:
                                Text(
                              _errorMessage!,
                              textAlign:
                                  TextAlign.center,
                              style:
                                  const TextStyle(
                                color:
                                    Colors.red,
                                fontSize:
                                    12,
                              ),
                            ),
                          ),

                        SizedBox(
                          width:
                              double.infinity,

                          child:
                              ElevatedButton(
                            onPressed:
                                _runPaddyClassificationTest,

                            style:
                                ElevatedButton
                                    .styleFrom(
                              backgroundColor:
                                  const Color(
                                0xFF4CAF7D,
                              ),

                              padding:
                                  const EdgeInsets
                                      .symmetric(
                                vertical:
                                    16,
                              ),

                              shape:
                                  RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius
                                        .circular(
                                  16,
                                ),
                              ),
                            ),

                            child:
                                Text(
                              'Analyze Paddy Sample',
                              style:
                                  GoogleFonts.poppins(
                                color:
                                    Colors.white,
                                fontWeight:
                                    FontWeight
                                        .w600,
                                fontSize:
                                    16,
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

class PaddyClassificationResultPage
    extends StatelessWidget {

  final File imageFile;
  final Map<String, dynamic>
      result;
  final String imageUrl;

  const PaddyClassificationResultPage({
    super.key,
    required this.imageFile,
    required this.result,
    required this.imageUrl,
  });

  @override
  Widget build(
    BuildContext context,
  ) {

    final String variety =
        result['variety']
                ?.toString() ??
            'Unknown';

    final String grade =
        result['grade']
                ?.toString() ??
            'Unknown';

    final double confidence =
        result['confidence']
                is num
            ? (result['confidence']
                    as num)
                .toDouble()
            : 0.0;

    final double? moisture =
        result['moisture'] is num
            ? (result['moisture']
                    as num)
                .toDouble()
            : null;

    return Scaffold(
      backgroundColor:
          const Color(0xFFF6F3ED),

      appBar: AppBar(
        backgroundColor:
            const Color(0xFFF6F3ED),
        elevation: 0,

        title:
            Text(
          'Paddy Classification Result',
          style:
              GoogleFonts.poppins(
            color:
                Colors.black87,
            fontWeight:
                FontWeight.w600,
          ),
        ),

        iconTheme:
            const IconThemeData(
          color: Colors.black87,
        ),
      ),

      body: SafeArea(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.all(
            20,
          ),

          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .stretch,

            children: [

              // --------------------------------------------------
              // CAPTURED IMAGE
              // --------------------------------------------------

              ClipRRect(
                borderRadius:
                    BorderRadius
                        .circular(24),

                child:
                    Image.file(
                  imageFile,
                  height: 300,
                  width:
                      double.infinity,
                  fit:
                      BoxFit.cover,
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              // --------------------------------------------------
              // MAIN RESULT
              // --------------------------------------------------

              Container(
                padding:
                    const EdgeInsets
                        .all(20),

                decoration:
                    BoxDecoration(
                  color:
                      Colors.white,
                  borderRadius:
                      BorderRadius
                          .circular(
                    24,
                  ),
                ),

                child: Column(
                  children: [

                    const Icon(
                      Icons
                          .grass_rounded,
                      size: 52,
                      color:
                          Color(
                        0xFF4CAF7D,
                      ),
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    Text(
                      variety,
                      textAlign:
                          TextAlign.center,

                      style:
                          GoogleFonts
                              .poppins(
                        fontSize: 25,
                        fontWeight:
                            FontWeight
                                .bold,
                        color:
                            Colors.black87,
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),

                      decoration:
                          BoxDecoration(
                        color: const Color(
                          0xFF4CAF7D,
                        ).withOpacity(0.12),
                        borderRadius:
                            BorderRadius
                                .circular(20),
                      ),

                      child: Text(
                        'Grade $grade',
                        style: GoogleFonts
                            .poppins(
                          fontSize: 14,
                          fontWeight:
                              FontWeight
                                  .w600,
                          color:
                              const Color(
                            0xFF2E7D53,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 16,
                    ),

                    Text(
                      'Confidence',
                      style:
                          GoogleFonts
                              .poppins(
                        fontSize: 14,
                        color:
                            Colors.black54,
                      ),
                    ),

                    const SizedBox(
                      height: 4,
                    ),

                    Text(
                      '${confidence.toStringAsFixed(2)}%',
                      style:
                          GoogleFonts
                              .poppins(
                        fontSize: 32,
                        fontWeight:
                            FontWeight
                                .bold,
                        color:
                            const Color(
                          0xFF4CAF7D,
                        ),
                      ),
                    ),

                    if (moisture != null) ...[
                      const SizedBox(
                        height: 16,
                      ),

                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .center,
                        children: [
                          const Icon(
                            Icons
                                .water_drop_rounded,
                            size: 16,
                            color: Colors
                                .blue,
                          ),
                          const SizedBox(
                            width: 6,
                          ),
                          Text(
                            '${moisture.toStringAsFixed(1)}% Moisture',
                            style: GoogleFonts
                                .poppins(
                              fontSize: 13,
                              color: Colors
                                  .black54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              // --------------------------------------------------
              // SAVED CONFIRMATION
              // --------------------------------------------------

              Container(
                padding:
                    const EdgeInsets
                        .all(16),

                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xFFE8F5E9,
                  ),
                  borderRadius:
                      BorderRadius
                          .circular(
                    18,
                  ),
                ),

                child: Row(
                  children: [

                    const Icon(
                      Icons
                          .cloud_done_rounded,
                      color:
                          Color(
                        0xFF2E7D53,
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child:
                          Text(
                        'This result and image have been saved to your history.',
                        style:
                            GoogleFonts
                                .poppins(
                          fontSize:
                              12,
                          color:
                              const Color(
                            0xFF2E7D53,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              // --------------------------------------------------
              // DONE
              // --------------------------------------------------

              SizedBox(
                width:
                    double.infinity,

                child:
                    ElevatedButton(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pop();
                  },

                  style:
                      ElevatedButton
                          .styleFrom(
                    backgroundColor:
                        const Color(
                      0xFF4CAF7D,
                    ),

                    padding:
                        const EdgeInsets
                            .symmetric(
                      vertical: 16,
                    ),

                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius
                              .circular(
                        16,
                      ),
                    ),
                  ),

                  child:
                      Text(
                    'Done',
                    style:
                        GoogleFonts
                            .poppins(
                      color:
                          Colors.white,
                      fontWeight:
                          FontWeight
                              .w600,
                      fontSize:
                          16,
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