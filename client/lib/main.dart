import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'screens/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ============================================================
  // FIREBASE
  // ============================================================

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ============================================================
  // START APP
  // ============================================================

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(
    BuildContext context,
  ) {
    return MaterialApp(
      title: 'Ankur',
      debugShowCheckedModeBanner: false,

      theme: ThemeData(
        useMaterial3: true,

        colorSchemeSeed:
            const Color(0xFFE7B45A),

        scaffoldBackgroundColor:
            const Color(0xFFFFF8EC),

        fontFamily: 'Poppins',
      ),

      // Your actual login widget is LoginPage.
      home: const LoginPage(),
    );
  }
}