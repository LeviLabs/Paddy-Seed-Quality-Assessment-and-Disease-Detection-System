import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'profile_page.dart';
import 'history.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<WeatherData> _weatherFuture;

  @override
  void initState() {
    super.initState();

    _weatherFuture = _loadWeather();
  }

  // ============================================================
  // WEATHER DATA (IP-based location — no GPS permission needed)
  // ============================================================

  Future<WeatherData> _loadWeather() async {
    // ------------------------------------------------------------
    // 1. Get approximate location + city name from IP address
    // ------------------------------------------------------------

    final _IpLocation loc = await _getIpLocation();

    final double latitude = loc.latitude;
    final double longitude = loc.longitude;
    final String locationName = loc.locationName;

    // ------------------------------------------------------------
    // 2. Get weather from Open-Meteo
    // ------------------------------------------------------------

    final Uri weatherUrl = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&current=temperature_2m,weather_code'
      '&daily=temperature_2m_max,temperature_2m_min'
      '&forecast_days=1'
      '&timezone=auto',
    );

    final http.Response response = await http.get(weatherUrl);

    if (response.statusCode != 200) {
      throw Exception(
        'Weather service unavailable.',
      );
    }

    final Map<String, dynamic> data =
        jsonDecode(
      response.body,
    ) as Map<String, dynamic>;

    final Map<String, dynamic> current =
        data['current']
            as Map<String, dynamic>;

    final Map<String, dynamic> daily =
        data['daily']
            as Map<String, dynamic>;

    final double temperature =
        (current['temperature_2m']
                as num)
            .toDouble();

    final int weatherCode =
        (current['weather_code']
                as num)
            .toInt();

    final List<dynamic> maxList =
        daily['temperature_2m_max']
            as List<dynamic>;

    final List<dynamic> minList =
        daily['temperature_2m_min']
            as List<dynamic>;

    final double maxTemperature =
        (maxList.first as num).toDouble();

    final double minTemperature =
        (minList.first as num).toDouble();

    return WeatherData(
      temperature: temperature,
      maxTemperature:
          maxTemperature,
      minTemperature:
          minTemperature,
      weatherCode: weatherCode,
      locationName: locationName,
    );
  }

  // ============================================================
  // IP-BASED LOCATION (with fallback providers)
  // ============================================================

  Future<_IpLocation> _getIpLocation() async {
    // Try each provider in order; move to the next on any failure
    // (bad status, rate limit, malformed body, timeout, etc).

    // --- Provider 1: ipapi.co ---------------------------------
    try {
      final http.Response res = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 8));

      debugPrint('ipapi.co status: ${res.statusCode}, body: ${res.body}');

      if (res.statusCode == 200) {
        final Map<String, dynamic> d =
            jsonDecode(res.body) as Map<String, dynamic>;

        if (d['error'] != true &&
            d['latitude'] != null &&
            d['longitude'] != null) {
          return _IpLocation(
            latitude: (d['latitude'] as num).toDouble(),
            longitude: (d['longitude'] as num).toDouble(),
            locationName: _firstNonEmpty(
              [d['city'] as String?, d['region'] as String?],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('ipapi.co failed: $e');
    }

    // --- Provider 2: ip-api.com (http only on free tier) ------
    try {
      final http.Response res = await http
          .get(Uri.parse('http://ip-api.com/json/'))
          .timeout(const Duration(seconds: 8));

      debugPrint('ip-api.com status: ${res.statusCode}, body: ${res.body}');

      if (res.statusCode == 200) {
        final Map<String, dynamic> d =
            jsonDecode(res.body) as Map<String, dynamic>;

        if (d['status'] == 'success' &&
            d['lat'] != null &&
            d['lon'] != null) {
          return _IpLocation(
            latitude: (d['lat'] as num).toDouble(),
            longitude: (d['lon'] as num).toDouble(),
            locationName: _firstNonEmpty(
              [d['city'] as String?, d['regionName'] as String?],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('ip-api.com failed: $e');
    }

    // --- Provider 3: freeipapi.com -----------------------------
    try {
      final http.Response res = await http
          .get(Uri.parse('https://freeipapi.com/api/json'))
          .timeout(const Duration(seconds: 8));

      debugPrint(
        'freeipapi.com status: ${res.statusCode}, body: ${res.body}',
      );

      if (res.statusCode == 200) {
        final Map<String, dynamic> d =
            jsonDecode(res.body) as Map<String, dynamic>;

        if (d['latitude'] != null && d['longitude'] != null) {
          return _IpLocation(
            latitude: (d['latitude'] as num).toDouble(),
            longitude: (d['longitude'] as num).toDouble(),
            locationName: _firstNonEmpty(
              [d['cityName'] as String?, d['regionName'] as String?],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('freeipapi.com failed: $e');
    }

    throw Exception(
      'Could not determine your location from any provider. '
      'Check internet connection / INTERNET permission in the manifest.',
    );
  }

  String _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.trim().isNotEmpty) return c.trim();
    }
    return 'Your Location';
  }

  // ============================================================
  // GREETING
  // ============================================================

  String _greetingLine1() {
    return 'Good';
  }

  String _greetingLine2() {
    final int hour =
        DateTime.now().hour;

    if (hour >= 5 && hour < 12) {
      return 'morning';
    } else if (hour >= 12 &&
        hour < 17) {
      return 'afternoon';
    } else if (hour >= 17 &&
        hour < 21) {
      return 'evening';
    } else {
      return 'night';
    }
  }

  // ============================================================
  // GREETING BACKGROUND
  // ============================================================

  String _greetingImage() {
    final int hour =
        DateTime.now().hour;

    if (hour >= 5 && hour < 12) {
      return 'assets/images/morning.png';
    } else if (hour >= 12 &&
        hour < 17) {
      return 'assets/images/afternoon.png';
    } else if (hour >= 17 &&
        hour < 21) {
      return 'assets/images/evening.png';
    } else {
      return 'assets/images/night.png';
    }
  }

  // ============================================================
  // PROFILE AVATAR
  // ============================================================

  Widget _profileAvatar() {
    final User? user =
        FirebaseAuth.instance.currentUser;

    final String? photoUrl =
        user?.photoURL;

    final String? displayName =
        user?.displayName ??
            user?.email;

    final String? initial =
        (displayName != null &&
                displayName.isNotEmpty)
            ? displayName[0]
                .toUpperCase()
            : null;

    return Container(
      padding:
          const EdgeInsets.all(3),
      decoration:
          const BoxDecoration(
        shape: BoxShape.circle,
        gradient:
            LinearGradient(
          begin:
              Alignment.topLeft,
          end:
              Alignment.bottomRight,
          colors: [
            Color(0xFF7FD8F7),
            Color(0xFF2196F3),
            Color(0xFF0B5FE0),
          ],
        ),
      ),
      child: CircleAvatar(
        radius: 25,
        backgroundColor:
            Colors.white
                .withOpacity(0.85),
        backgroundImage:
            photoUrl != null
                ? NetworkImage(
                    photoUrl,
                  )
                : null,
        child: photoUrl != null
            ? null
            : initial != null
                ? Text(
                    initial,
                    style:
                        GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.w600,
                      color:
                          Colors.black87,
                    ),
                  )
                : const Icon(
                    Icons
                        .person_rounded,
                    color:
                        Colors.black54,
                    size: 22,
                  ),
      ),
    );
  }

  // ============================================================
  // WEATHER DESCRIPTION
  // ============================================================

  String _weatherDescription(
    int code,
  ) {
    switch (code) {
      case 0:
        return 'Clear';

      case 1:
        return 'Mainly Clear';

      case 2:
        return 'Partly Cloudy';

      case 3:
        return 'Cloudy';

      case 45:
      case 48:
        return 'Foggy';

      case 51:
      case 53:
      case 55:
        return 'Drizzle';

      case 56:
      case 57:
        return 'Freezing Drizzle';

      case 61:
      case 63:
      case 65:
        return 'Rain';

      case 66:
      case 67:
        return 'Freezing Rain';

      case 71:
      case 73:
      case 75:
      case 77:
        return 'Snow';

      case 80:
      case 81:
      case 82:
        return 'Rain Showers';

      case 85:
      case 86:
        return 'Snow Showers';

      case 95:
      case 96:
      case 99:
        return 'Thunderstorm';

      default:
        return 'Unknown';
    }
  }

  // ============================================================
  // WEATHER ICON
  // ============================================================

  IconData _weatherIcon(
    int code,
  ) {
    switch (code) {
      case 0:
        return Icons
            .wb_sunny_rounded;

      case 1:
        return Icons
            .wb_sunny_rounded;

      case 2:
        return Icons
            .cloud_queue_rounded;

      case 3:
        return Icons
            .cloud_rounded;

      case 45:
      case 48:
        return Icons.foggy;

      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return Icons
            .water_drop_rounded;

      case 61:
      case 63:
      case 65:
      case 66:
      case 67:
      case 80:
      case 81:
      case 82:
        return Icons
            .water_drop_rounded;

      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return Icons
            .ac_unit_rounded;

      case 95:
      case 96:
      case 99:
        return Icons
            .thunderstorm_rounded;

      default:
        return Icons
            .cloud_rounded;
    }
  }

  // ============================================================
  // WEATHER CARD
  // ============================================================

  Widget _weatherCard() {
    return FutureBuilder<WeatherData>(
      future: _weatherFuture,
      builder: (
        context,
        snapshot,
      ) {
        if (snapshot.connectionState ==
            ConnectionState.waiting) {
          return _weatherLoadingCard();
        }

        if (snapshot.hasError ||
            !snapshot.hasData) {
          return _weatherErrorCard();
        }

        final WeatherData weather =
            snapshot.data!;

        return _weatherDataCard(
          weather,
        );
      },
    );
  }

  // ============================================================
  // WEATHER LOADING CARD
  // ============================================================

  Widget _weatherLoadingCard() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding:
          const EdgeInsets.all(18),
      decoration:
          const BoxDecoration(
        borderRadius:
            BorderRadius.all(
          Radius.circular(24),
        ),
        gradient:
            LinearGradient(
          begin:
              Alignment.topCenter,
          end:
              Alignment.bottomCenter,
          colors: [
            Color(0xFF4F7FC1),
            Color(0xFF617DC3),
            Color(0xFFB9A7B9),
          ],
        ),
      ),
      child: const Center(
        child:
            CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        ),
      ),
    );
  }

  // ============================================================
  // WEATHER ERROR CARD
  // ============================================================

  Widget _weatherErrorCard() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _weatherFuture =
              _loadWeather();
        });
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding:
            const EdgeInsets.all(18),
        decoration:
            const BoxDecoration(
          borderRadius:
              BorderRadius.all(
            Radius.circular(24),
          ),
          gradient:
              LinearGradient(
            begin:
                Alignment.topCenter,
            end:
                Alignment.bottomCenter,
            colors: [
              Color(0xFF4F7FC1),
              Color(0xFF617DC3),
              Color(0xFFB9A7B9),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons
                  .location_off_rounded,
              color: Colors.white,
              size: 36,
            ),

            const SizedBox(
              height: 10,
            ),

            Text(
              'Weather unavailable',
              style:
                  GoogleFonts.poppins(
                color:
                    Colors.white,
                fontSize: 15,
                fontWeight:
                    FontWeight.w600,
              ),
            ),

            const SizedBox(
              height: 4,
            ),

            Text(
              'Tap to try again',
              style:
                  GoogleFonts.poppins(
                color: Colors.white
                    .withOpacity(0.75),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // WEATHER DATA CARD
  // ============================================================

  Widget _weatherDataCard(
    WeatherData weather,
  ) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
        16,
        14,
        14,
        14,
      ),
      decoration:
          const BoxDecoration(
        borderRadius:
            BorderRadius.all(
          Radius.circular(24),
        ),
        gradient:
            LinearGradient(
          begin:
              Alignment.topCenter,
          end:
              Alignment.bottomCenter,
          colors: [
            Color(0xFF4F7FC1),
            Color(0xFF617DC3),
            Color(0xFFB9A7B9),
          ],
          stops: [
            0.0,
            0.55,
            1.0,
          ],
        ),
      ),
      child: Stack(
        children: [
          Align(
            alignment:
                Alignment.topLeft,
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  weather.temperature
                      .round()
                      .toString(),
                  style:
                      GoogleFonts.poppins(
                    fontSize: 55,
                    fontWeight:
                        FontWeight.w300,
                    color:
                        Colors.white,
                    height: 0.95,
                  ),
                ),
                Text(
                  '°',
                  style:
                      GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight:
                        FontWeight.w400,
                    color:
                        const Color(
                      0xFFB9C9E9,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Align(
            alignment:
                Alignment.topRight,
            child: Icon(
              _weatherIcon(
                weather.weatherCode,
              ),
              size: 48,
              color:
                  const Color(
                0xFFFFE7A4,
              ),
            ),
          ),

          Align(
            alignment:
                Alignment.bottomLeft,
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  _weatherDescription(
                    weather.weatherCode,
                  ),
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight:
                        FontWeight.w500,
                    color:
                        Colors.white,
                  ),
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  '${weather.maxTemperature.round()}° / '
                  '${weather.minTemperature.round()}°',
                  style:
                      GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w600,
                    color:
                        Colors.white,
                  ),
                ),

                const SizedBox(
                  height: 6,
                ),

                Text(
                  weather.locationName,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight:
                        FontWeight.w400,
                    color: Colors.white
                        .withOpacity(
                      0.62,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MOOD CARD
  // ============================================================

  static Widget _moodCard({
    required String title,
    required String subtitle,
    required Color color,
    IconData? icon,
    required bool largeTitle,
    String? backgroundImage,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius:
            BorderRadius.circular(24),
      ),
      child: ClipRRect(
        borderRadius:
            BorderRadius.circular(24),
        child: Stack(
          children: [
            if (backgroundImage != null)
              Positioned.fill(
                child: Image.asset(
                  backgroundImage,
                  fit: BoxFit.cover,
                ),
              ),

            if (backgroundImage != null)
              Positioned.fill(
                child: Container(
                  decoration:
                      BoxDecoration(
                    gradient:
                        LinearGradient(
                      begin:
                          Alignment.topCenter,
                      end:
                          Alignment.bottomCenter,
                      colors: [
                        Colors.black
                            .withOpacity(
                          0.12,
                        ),
                        Colors.transparent,
                        Colors.black
                            .withOpacity(
                          0.04,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            Padding(
              padding:
                  const EdgeInsets.all(
                18,
              ),
              child: Align(
                alignment:
                    Alignment.topLeft,
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      title,
                      style:
                          GoogleFonts.poppins(
                        fontSize:
                            largeTitle
                                ? 24
                                : 21,
                        fontWeight:
                            FontWeight.bold,
                        color:
                            Colors.white,
                        height: 1.05,
                      ),
                    ),

                    const SizedBox(
                      height: 5,
                    ),

                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white
                            .withOpacity(
                          0.85,
                        ),
                        fontWeight:
                            FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (icon != null)
              Positioned(
                right: 18,
                bottom: 18,
                child: Icon(
                  icon,
                  size: 62,
                  color: Colors.white
                      .withOpacity(
                    0.92,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CAMERA CARD → OPTIONS SHEET → CAMERA CAPTURE
  // ============================================================

  void _showCameraOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          decoration: const BoxDecoration(
            color: Color(0xFF4CAF7D),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(28),
            ),
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
                  color: Colors.white.withOpacity(0.85),
                ),
              ),
              const SizedBox(height: 22),
              _cameraOptionTile(
                context: sheetContext,
                icon: Icons.coronavirus_rounded,
                title: 'Plant Disease',
                subtitle: 'Scan a leaf for disease detection',
                testType: 'plant_disease',
              ),
              const SizedBox(height: 14),
              _cameraOptionTile(
                context: sheetContext,
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

  Widget _cameraOptionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required String testType,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _pickImageForTest(testType);
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
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImageForTest(String testType) async {
    final ImagePicker picker = ImagePicker();

    XFile? photo;
    try {
      photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
    } catch (e) {
      debugPrint('Camera error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open camera')),
        );
      }
      return;
    }

    if (photo == null) return; // user cancelled

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TestPreviewPage(
          imageFile: File(photo!.path),
          testType: testType,
        ),
      ),
    );
  }

  // ============================================================
  // MOOD GRID
  // ============================================================

  Widget _buildMoodGrid(
    BuildContext context,
  ) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment
                .stretch,
        children: [
          Expanded(
            child: Column(
              children: [
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onTap: () => _showCameraOptions(context),
                    child: _moodCard(
                      title: 'Camera',
                      subtitle:
                          'Hold steady for a clear read',
                      color:
                          const Color(
                        0xFF4CAF7D,
                      ),
                      icon: null,
                      backgroundImage:
                          'assets/images/camera.png',
                      largeTitle: true,
                    ),
                  ),
                ),

                const SizedBox(
                  height: 14,
                ),

                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => HistoryPage.show(context),
                    child: _moodCard(
                      title:
                          'Test History',
                      subtitle:
                          'Track your history',
                      color:
                          const Color(
                        0xFFEC4899,
                      ),
                      icon: null,
                      backgroundImage:
                          'assets/images/history.png',
                      largeTitle: false,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            width: 14,
          ),

          Expanded(
            child: Column(
              children: [
                Expanded(
                  flex: 2,
                  child:
                      _weatherCard(),
                ),

                const SizedBox(
                  height: 14,
                ),

                Expanded(
                  flex: 3,
                  child: _moodCard(
                    title:
                        'Chatbot',
                    subtitle:
                        'Ask anything, anytime',
                    color:
                        const Color(
                      0xFFF0A83A,
                    ),
                    icon: null,
                    backgroundImage:
                        'assets/images/chatbot.png',
                    largeTitle: false,
                  ),
                ),
              ],
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
  Widget build(
    BuildContext context,
  ) {
    final double screenHeight =
        MediaQuery.of(context)
            .size
            .height;

    final double statusBarHeight =
        MediaQuery.of(context).padding.top;

    final double headerHeight =
        screenHeight * 0.35 + statusBarHeight;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor:
            const Color(0xFFF6F3ED),
        extendBodyBehindAppBar: true,

        body: Column(
          children: [
            SizedBox(
              height: headerHeight,
              width: double.infinity,
              child: Container(
                decoration:
                    BoxDecoration(
                  borderRadius:
                      const BorderRadius
                          .only(
                    bottomLeft:
                        Radius.circular(32),
                    bottomRight:
                        Radius.circular(32),
                  ),
                  image:
                      DecorationImage(
                    image: AssetImage(
                      _greetingImage(),
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius
                          .only(
                    bottomLeft:
                        Radius.circular(32),
                    bottomRight:
                        Radius.circular(32),
                  ),
                  child: Padding(
                    padding:
                        EdgeInsets
                            .fromLTRB(
                      20,
                      statusBarHeight + 16,
                      20,
                      20,
                    ),
                    child: Stack(
                      children: [
                        Align(
                          alignment:
                              Alignment.topLeft,
                          child: Column(
                            mainAxisSize:
                                MainAxisSize
                                    .min,
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              const SizedBox(
                                height: 10,
                              ),

                              Text(
                                _greetingLine1(),
                                style:
                                    GoogleFonts
                                        .poppins(
                                  fontSize: 44,
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                  color:
                                      Colors.white,
                                  height:
                                      1.05,
                                ),
                              ),

                              Text(
                                _greetingLine2(),
                                style:
                                    GoogleFonts
                                        .poppins(
                                  fontSize: 44,
                                  fontWeight:
                                      FontWeight
                                          .bold,
                                  color:
                                      Colors.white,
                                  height:
                                      1.05,
                                ),
                              ),
                            ],
                          ),
                        ),

                        Positioned(
                          top: 8,
                          right: 0,
                          child:
                              GestureDetector(
                            onTap: () {
                              ProfilePage
                                  .show(
                                context,
                              );
                            },
                            child:
                                _profileAvatar(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            Expanded(
              child: SafeArea(
                top: false,
                child: _buildMoodGrid(
                  context,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// IP LOCATION RESULT
// ================================================================

class _IpLocation {
  final double latitude;
  final double longitude;
  final String locationName;

  const _IpLocation({
    required this.latitude,
    required this.longitude,
    required this.locationName,
  });
}

// ================================================================
// WEATHER MODEL
// ================================================================

class WeatherData {
  final double temperature;
  final double maxTemperature;
  final double minTemperature;
  final int weatherCode;
  final String locationName;

  const WeatherData({
    required this.temperature,
    required this.maxTemperature,
    required this.minTemperature,
    required this.weatherCode,
    required this.locationName,
  });
}

// ================================================================
// TEST PREVIEW PAGE
// ================================================================
class _TestPreviewPage extends StatefulWidget {
  final File imageFile;
  final String testType;

  const _TestPreviewPage({
    required this.imageFile,
    required this.testType,
  });

  @override
  State<_TestPreviewPage> createState() => _TestPreviewPageState();
}

class _TestPreviewPageState extends State<_TestPreviewPage> {
  bool _isRunning = false;

  String get _testLabel {
    return widget.testType == 'plant_disease'
        ? 'Plant Disease'
        : 'Paddy Classification';
  }

  Future<void> _runTest() async {
    setState(() => _isRunning = true);

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    setState(() => _isRunning = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$_testLabel analysis complete')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F3ED),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F3ED),
        elevation: 0,
        title: Text(
          _testLabel,
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
          child: Column(
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
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isRunning ? null : _runTest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF7D),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isRunning
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Analyze $_testLabel',
                          style: const TextStyle(
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