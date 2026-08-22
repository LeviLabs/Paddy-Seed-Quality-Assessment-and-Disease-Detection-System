import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ================================================================
// HISTORY ENTRY MODEL
// ================================================================
// Generic enough to cover both "Plant Disease" and
// "Paddy Classification" results. Swap the sample data in
// `_HistoryPageState._loadHistory()` for your real API/DB call
// whenever it's ready — everything else just renders this model.

enum HistoryTestType { plantDisease, paddyClassification }

class HistoryEntry {
  final String id;
  final HistoryTestType testType;
  final String imagePath; // asset path, file path, or network URL
  final bool isNetworkImage;
  final String title; // e.g. "Paddy Sample #24"
  final String subtitle; // e.g. "IR64 Variety" or disease name
  final String resultLabel; // e.g. "Grade A" or "Healthy"
  final Color resultColor;
  final DateTime date;
  final String? moistureLabel; // e.g. "12.4% Moisture" (paddy only)

  const HistoryEntry({
    required this.id,
    required this.testType,
    required this.imagePath,
    required this.title,
    required this.subtitle,
    required this.resultLabel,
    required this.resultColor,
    required this.date,
    this.isNetworkImage = false,
    this.moistureLabel,
  });
}

// ================================================================
// HISTORY PAGE — call HistoryPage.show(context) to open it
// ================================================================
// Slides up from the bottom with rounded top corners, like a
// tall modal sheet, and dims the screen behind it.

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const HistoryPage(),
    );
  }

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late Future<List<HistoryEntry>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  // ------------------------------------------------------------
  // Replace this with your real data source (local DB, API, etc).
  // Left as sample data so the page renders end-to-end right away.
  // ------------------------------------------------------------
  Future<List<HistoryEntry>> _loadHistory() async {
    await Future.delayed(const Duration(milliseconds: 300));

    return [
      HistoryEntry(
        id: '24',
        testType: HistoryTestType.paddyClassification,
        imagePath: 'assets/images/sample_paddy_1.png',
        title: 'Paddy Sample #24',
        subtitle: 'IR64 Variety',
        resultLabel: 'Grade A',
        resultColor: const Color(0xFF2E7D53),
        date: DateTime(2025, 5, 16),
        moistureLabel: '12.4% Moisture',
      ),
      HistoryEntry(
        id: '23',
        testType: HistoryTestType.plantDisease,
        imagePath: 'assets/images/sample_leaf_1.png',
        title: 'Leaf Scan #23',
        subtitle: 'Bacterial Leaf Blight',
        resultLabel: 'At Risk',
        resultColor: const Color(0xFFD97706),
        date: DateTime(2025, 5, 12),
      ),
      HistoryEntry(
        id: '22',
        testType: HistoryTestType.paddyClassification,
        imagePath: 'assets/images/sample_paddy_2.png',
        title: 'Paddy Sample #22',
        subtitle: 'Basmati Variety',
        resultLabel: 'Grade B',
        resultColor: const Color(0xFFCA8A04),
        date: DateTime(2025, 5, 9),
        moistureLabel: '14.1% Moisture',
      ),
      HistoryEntry(
        id: '21',
        testType: HistoryTestType.plantDisease,
        imagePath: 'assets/images/sample_leaf_2.png',
        title: 'Leaf Scan #21',
        subtitle: 'No Disease Detected',
        resultLabel: 'Healthy',
        resultColor: const Color(0xFF2E7D53),
        date: DateTime(2025, 5, 3),
      ),
    ];
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.9,
      decoration: const BoxDecoration(
        color: Color(0xFFF6F3ED),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          _dragHandle(),
          _header(),
          Expanded(
            child: FutureBuilder<List<HistoryEntry>>(
              future: _historyFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF4CAF7D),
                      strokeWidth: 2,
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return _emptyOrErrorState(
                    icon: Icons.error_outline_rounded,
                    title: 'Could not load history',
                    subtitle: 'Pull down and try again',
                  );
                }

                final List<HistoryEntry> entries =
                    snapshot.data ?? const [];

                if (entries.isEmpty) {
                  return _emptyOrErrorState(
                    icon: Icons.history_rounded,
                    title: 'No scans yet',
                    subtitle:
                        'Your analyzed photos will show up here',
                  );
                }

                return RefreshIndicator(
                  color: const Color(0xFF4CAF7D),
                  onRefresh: () async {
                    setState(() {
                      _historyFuture = _loadHistory();
                    });
                    await _historyFuture;
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      4,
                      20,
                      24,
                    ),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      return _HistoryCard(
                        entry: entries[index],
                        onTap: () {
                          // TODO: navigate to a detail page for
                          // entries[index] whenever that's ready.
                        },
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

  // ------------------------------------------------------------
  // DRAG HANDLE
  // ------------------------------------------------------------

  Widget _dragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.15),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // HEADER
  // ------------------------------------------------------------

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Test History',
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // EMPTY / ERROR STATE
  // ------------------------------------------------------------

  Widget _emptyOrErrorState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Colors.black26),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black.withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// HISTORY CARD — matches the reference design:
// circular thumbnail, title, colored subtitle, result pill + chevron,
// date + (optional) moisture row with icons.
// ================================================================

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  final VoidCallback? onTap;

  const _HistoryCard({
    required this.entry,
    this.onTap,
  });

  String _formattedDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumbnail(),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        _resultPill(),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.black38,
                          size: 20,
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF2E7D53),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 13,
                          color: Colors.black.withOpacity(0.4),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _formattedDate(entry.date),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black.withOpacity(0.55),
                          ),
                        ),

                        if (entry.moistureLabel != null) ...[
                          const SizedBox(width: 14),
                          Icon(
                            Icons.water_drop_rounded,
                            size: 13,
                            color: Colors.blue.withOpacity(0.55),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            entry.moistureLabel!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black.withOpacity(0.55),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbnail() {
    ImageProvider image;

    if (entry.imagePath.startsWith('data:image') || entry.imagePath.length > 300) {
      try {
        final String rawBase64 = entry.imagePath.contains(',')
            ? entry.imagePath.split(',').last
            : entry.imagePath;
        final Uint8List bytes = base64Decode(rawBase64);
        image = MemoryImage(bytes);
      } catch (_) {
        image = AssetImage(entry.imagePath);
      }
    } else if (entry.isNetworkImage || entry.imagePath.startsWith('http')) {
      image = NetworkImage(entry.imagePath);
    } else if (File(entry.imagePath).existsSync()) {
      image = FileImage(File(entry.imagePath));
    } else {
      image = AssetImage(entry.imagePath);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image(
        image: image,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 56,
            height: 56,
            color: const Color(0xFFF0EBE0),
            child: Icon(
              entry.testType == HistoryTestType.paddyClassification
                  ? Icons.grass_rounded
                  : Icons.eco_rounded,
              color: Colors.black26,
            ),
          );
        },
      ),
    );
  }

  Widget _resultPill() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: entry.resultColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        entry.resultLabel,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: entry.resultColor,
        ),
      ),
    );
  }
}