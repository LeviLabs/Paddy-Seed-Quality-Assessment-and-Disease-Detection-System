import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_screen.dart';

class LanguageSelectionPage extends StatefulWidget {
  const LanguageSelectionPage({super.key});

  @override
  State<LanguageSelectionPage> createState() => _LanguageSelectionPageState();
}

class _LanguageSelectionPageState extends State<LanguageSelectionPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  String _selectedLanguage = "";
  bool _loading = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveLanguage() async {
    if (_loading) return;

    setState(() {
      _loading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) return;

      await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
        "uid": user.uid,
        "name": user.displayName,
        "email": user.email,
        "photo": user.photoURL,
        "language": _selectedLanguage,
        "languageSelected": true,
        "updatedAt": FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to save language\n$e")));
    }
  }

  Widget languageTile({
    required String title,
    required String subtitle,
    required String value,
    required String flag,
    double titleFontSize = 30,
    double subtitleFontSize = 17,
  }) {
    final selected = value == _selectedLanguage;

    return InkWell(
      borderRadius: BorderRadius.circular(25),
      onTap: () {
        setState(() {
          _selectedLanguage = value;
        });

        _saveLanguage();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: selected ? Colors.orange : Colors.orange.shade100,
          ),
          boxShadow: const [
            BoxShadow(
              blurRadius: 10,
              color: Colors.black12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(radius: 28, backgroundImage: AssetImage(flag)),

            const SizedBox(width: 18),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 0), // was 5 — tighter gap to subtitle
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: subtitleFontSize,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),

            Container(
              height: 55,
              width: 55,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xffffefc8),
              ),
              child: _loading && selected
                  ? const Padding(
                      padding: EdgeInsets.all(15),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange,
                      ),
                    )
                  : const Icon(Icons.arrow_forward_ios, size: 24),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _animation,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                "assets/images/language_bg.png",
                fit: BoxFit.cover,
              ),
            ),

            Positioned(
              left: 45,
              right: 45,
              top: 555,
              child: Column(
                children: [
                  languageTile(
                    title: "हिन्दी",
                    subtitle: "ऐप को हिंदी में उपयोग करें",
                    value: "hi",
                    flag: "assets/icons/india.png",
                    titleFontSize: 24, // Hindi title size
                    subtitleFontSize: 14, // Hindi subtitle size
                  ),

                  const SizedBox(height: 18),

                  languageTile(
                    title: "English",
                    subtitle: "Continue in English",
                    value: "en",
                    flag: "assets/icons/uk.png",
                    titleFontSize: 24, // English title size
                    subtitleFontSize: 14, // English subtitle size
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
