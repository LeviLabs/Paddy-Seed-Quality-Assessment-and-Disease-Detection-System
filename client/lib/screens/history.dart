import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/paddy_storage_service.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const HistoryPage(),
  );
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Future<List<_Scan>>? _future;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = _load();

  Future<List<_Scan>> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid);
    final scans = <_Scan>[];
    final seen = <String>{};
    final errors = <String>[];
    var successfulCollections = 0;

    // New scans use test_history; earlier app versions may have used tests.
    // Keep them separate: a document ID can exist in both collections.
    for (final collectionName in <String>['test_history', 'tests']) {
      try {
        final query = await userRef
            .collection(collectionName)
            .limit(500)
            .get()
            .timeout(const Duration(seconds: 20));
        successfulCollections++;

        for (final doc in query.docs) {
          final key = '$collectionName/${doc.id}';
          if (!seen.add(key)) continue;

          final data = doc.data();
          final imageUrl = (data['imageUrl'] ?? data['image_url'] ?? '')
              .toString();
          final dynamic rawDate =
              data['createdAt'] ?? data['timestamp'] ?? data['createdAtLocal'];
          DateTime date;
          if (rawDate is Timestamp) {
            date = rawDate.toDate();
          } else if (rawDate is DateTime) {
            date = rawDate;
          } else if (rawDate is num) {
            // Older records may save Unix time in seconds or milliseconds.
            final milliseconds = rawDate < 100000000000
                ? (rawDate * 1000).round()
                : rawDate.round();
            date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
          } else {
            date =
                DateTime.tryParse(rawDate?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);
          }

          scans.add(_Scan(key, data, date, imageUrl));
        }
      } catch (error) {
        debugPrint('History load failed for $collectionName: $error');
        errors.add('$collectionName: $error');
      }
    }

    // Don't incorrectly report "No scans" when both reads were blocked.
    if (successfulCollections == 0) {
      throw StateError('Unable to read scan history. ${errors.join(' | ')}');
    }

    scans.sort((a, b) => b.date.compareTo(a.date));
    return scans;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.sizeOf(context).height * .90,
      decoration: const BoxDecoration(
        color: Color(0xFFF6F3ED),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Test History',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(_reload),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<_Scan>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _centerText('Could not load history', '${snap.error}');
                }
                final scans = snap.data ?? [];
                if (scans.isEmpty) {
                  return _centerText(
                    'No scans yet',
                    FirebaseAuth.instance.currentUser == null
                        ? 'Sign in to save and view your scans.'
                        : 'Your next analysis will appear here.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    setState(_reload);
                    await _future;
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
                    itemCount: scans.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final scan = scans[i];
                      return Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _showDetail(scan),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                _image(scan, 66),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        scan.isPaddy
                                            ? 'Paddy Classification'
                                            : 'Plant Disease',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        scan.name.replaceAll('_', ' '),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          color: const Color(0xFF2E7D53),
                                        ),
                                      ),
                                      Text(
                                        '${scan.confidence.toStringAsFixed(2)}% • ${scan.date.day}/${scan.date.month}/${scan.date.year}',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Colors.black38,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _centerText(String title, String detail) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history, size: 42, color: Colors.black38),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(detail, textAlign: TextAlign.center),
        ],
      ),
    ),
  );

  Widget _image(_Scan scan, double size) {
    Widget child;
    if (scan.imagePath.isNotEmpty) {
      child = FutureBuilder<String>(
        future: scan.signedUrl,
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url != null && url.isNotEmpty) {
            return Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stackTrace) => _placeholder(scan),
            );
          }
          return _placeholder(scan);
        },
      );
    } else if (scan.url.isNotEmpty) {
      child = Image.network(
        scan.url,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stackTrace) => _placeholder(scan),
      );
    } else if (scan.legacyBase64.isNotEmpty) {
      try {
        final Uint8List bytes = base64Decode(scan.legacyBase64);
        child = Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(scan),
        );
      } catch (_) {
        child = _placeholder(scan);
      }
    } else {
      child = _placeholder(scan);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(width: size, height: size, child: child),
    );
  }

  Widget _placeholder(_Scan scan) => Container(
    color: const Color(0xFFF0EBE0),
    child: Icon(scan.isPaddy ? Icons.grass : Icons.eco, color: Colors.black38),
  );

  void _showDetail(_Scan scan) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: .85,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Scan Details',
                        style: GoogleFonts.poppins(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Center(child: _image(scan, 240)),
                const SizedBox(height: 20),
                Text(
                  scan.name.replaceAll('_', ' '),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Confidence: ${scan.confidence.toStringAsFixed(2)}%',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    fontSize: 17,
                    color: const Color(0xFF2E7D53),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Recorded: ${scan.date.toLocal()}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Predictions',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                ),
                ...scan.predictions.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(entry.key.replaceAll('_', ' '))),
                        Text(
                          entry.value is num
                              ? '${(entry.value as num).toStringAsFixed(2)}%'
                              : entry.value.toString(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Scan {
  final String id;
  final Map<String, dynamic> data;
  final DateTime date;
  final String url;
  _Scan(this.id, this.data, this.date, this.url);
  Future<String>? _cachedSignedUrl;
  String get imagePath =>
      (data['imagePath'] ?? data['image_path'] ?? '').toString();
  Future<String> get signedUrl =>
      _cachedSignedUrl ??= PaddyStorageService.signedImageUrl(imagePath)
          .timeout(const Duration(seconds: 12), onTimeout: () => '')
          .catchError((Object error) {
            debugPrint('History image unavailable: $error');
            return '';
          });
  bool get isPaddy {
    final type = (data['testType'] ?? data['test_type'] ?? '')
        .toString()
        .toLowerCase();
    return type == 'paddy_classification' ||
        type == 'paddy' ||
        type == 'paddy_seed' ||
        (type.isEmpty && data.containsKey('variety'));
  }

  String get name =>
      (isPaddy
              ? (data['variety'] ??
                    data['prediction'] ??
                    data['predictedClass'])
              : (data['disease'] ??
                    data['prediction'] ??
                    data['predictedClass']))
          ?.toString() ??
      'Unknown';
  double get confidence {
    final raw = data['confidence'];
    return raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic> get predictions => data['predictions'] is Map
      ? Map<String, dynamic>.from(data['predictions'] as Map)
      : {};
  String get legacyBase64 =>
      (data['imageBase64'] ?? data['image_base64'] ?? '').toString();
}
