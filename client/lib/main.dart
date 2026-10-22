import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'screens/login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  if (key.isEmpty) {
    throw StateError(
      'SUPABASE_PUBLISHABLE_KEY missing. Run with --dart-define-from-file.',
    );
  }
  await Supabase.initialize(
    url: 'https://cwveknxneqtcgwmsporz.supabase.co',
    publishableKey: key,
    accessToken: () async => FirebaseAuth.instance.currentUser?.getIdToken(),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Ankur',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorSchemeSeed: const Color(0xFFE7B45A),
      scaffoldBackgroundColor: const Color(0xFFFFF8EC),
      fontFamily: 'Poppins',
    ),
    home: const LoginPage(),
  );
}
