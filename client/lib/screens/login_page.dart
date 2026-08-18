import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_screen.dart';
import 'language_selection_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  // ============================================================
  // ANIMATION
  // ============================================================

  late AnimationController _animationController;

  late Animation<Offset> _logoSlideAnimation;
  late Animation<Offset> _taglineSlideAnimation;
  late Animation<Offset> _buttonSlideAnimation;

  // ============================================================
  // GOOGLE SIGN IN
  // ============================================================

  bool _isGoogleSigningIn = false;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
  );

  // ============================================================
  // INIT STATE
  // ============================================================

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 1600,
      ),
    );

    _logoSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(
          0.0,
          0.6,
          curve: Curves.easeOutQuart,
        ),
      ),
    );

    _taglineSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 2.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(
          0.2,
          0.8,
          curve: Curves.easeOutQuart,
        ),
      ),
    );

    _buttonSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 2.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(
          0.4,
          1.0,
          curve: Curves.easeOutQuart,
        ),
      ),
    );

    _animationController.forward();
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.jpg',
              fit: BoxFit.cover,
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(
                  height: 20,
                ),

                // Logo
                _buildLogoSection(),

                const SizedBox(
                  height: 11,
                ),

                // Tagline
                SlideTransition(
                  position: _taglineSlideAnimation,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 50.0,
                    ),
                    child: Text(
                      'Healthy Seeds.\nSmarter Farming.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        color: Color.fromARGB(
                          218,
                          181,
                          135,
                          10,
                        ),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                  height: 40,
                ),

                // Google button
                SlideTransition(
                  position: _buttonSlideAnimation,
                  child: Transform.translate(
                    offset: const Offset(
                      0,
                      190,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                      ),
                      child: _buildGoogleSignUpButton(),
                    ),
                  ),
                ),

                const SizedBox(
                  height: 55,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LOGO
  // ============================================================

  Widget _buildLogoSection() {
    return SizedBox(
      height: 420,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            bottom: -40,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _logoSlideAnimation,
              child: Image.asset(
                'assets/images/logo.png',
                height: 300,
                width: 300,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // GOOGLE BUTTON
  // ============================================================

  Widget _buildGoogleSignUpButton() {
    return SizedBox(
      width: double.infinity,
      height: 65,
      child: ElevatedButton.icon(
        onPressed: _isGoogleSigningIn
            ? null
            : _handleGoogleSignIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          disabledBackgroundColor: Colors.white,
          foregroundColor: Colors.black,
          disabledForegroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(40),
          ),
          elevation: 2,
        ),
        icon: SvgPicture.asset(
          'assets/images/google.svg',
          width: 28,
          height: 28,
        ),
        label: _isGoogleSigningIn
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : const Text(
                'Continue with Google',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
      ),
    );
  }

  // ============================================================
  // GOOGLE SIGN IN
  // ============================================================

  Future<void> _handleGoogleSignIn() async {
    if (_isGoogleSigningIn) {
      return;
    }

    setState(() {
      _isGoogleSigningIn = true;
    });

    try {
      // ----------------------------------------------------------
      // Google account
      // ----------------------------------------------------------

      final GoogleSignInAccount? googleUser =
          await _googleSignIn.signIn();

      // User cancelled Google login.
      if (googleUser == null) {
        if (mounted) {
          setState(() {
            _isGoogleSigningIn = false;
          });
        }

        return;
      }

      // ----------------------------------------------------------
      // Google authentication
      // ----------------------------------------------------------

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // ----------------------------------------------------------
      // Firebase credential
      // ----------------------------------------------------------

      final AuthCredential credential =
          GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // ----------------------------------------------------------
      // Firebase login
      // ----------------------------------------------------------

      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(
        credential,
      );

      final User? user = userCredential.user;

      if (user == null) {
        throw Exception(
          'Unable to create Firebase user.',
        );
      }

      // ----------------------------------------------------------
      // Save/update basic user information
      // ----------------------------------------------------------

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(
        {
          'uid': user.uid,
          'email': user.email,
          'name': user.displayName ?? '',
          'photoUrl': user.photoURL ?? '',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(
          merge: true,
        ),
      );

      // ----------------------------------------------------------
      // CHECK LANGUAGE FROM FIRESTORE
      // ----------------------------------------------------------

      final DocumentSnapshot<Map<String, dynamic>> userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      final Map<String, dynamic>? userData = userDoc.data();

      final bool languageSelected =
          userDoc.exists &&
          userData != null &&
          userData['languageSelected'] == true &&
          userData['language'] != null &&
          userData['language'].toString().isNotEmpty;

      if (!mounted) {
        return;
      }

      // ----------------------------------------------------------
      // NAVIGATION
      // ----------------------------------------------------------

      if (languageSelected) {
        // Existing user:
        // Language already saved in Firestore.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const HomeScreen(),
          ),
        );
      } else {
        // New user:
        // Language has not been selected yet.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const LanguageSelectionPage(),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      debugPrint(
        'Firebase Auth Error: ${e.code}',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Login failed: ${e.message ?? e.code}',
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Google Sign-In Error: $e',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Login Failed\n$e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleSigningIn = false;
        });
      }
    }
  }
}