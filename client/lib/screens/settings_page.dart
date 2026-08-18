import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool darkMode = false;

  String selectedLanguage = "English";

  Future<void> logout() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const IntroPage()),
      (route) => false,
    );
  }

  void changeLanguage() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),

              const Text(
                "Choose Language",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 20),

              ListTile(
                leading: const Icon(Icons.language),
                title: const Text("English"),
                trailing: selectedLanguage == "English"
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  setState(() {
                    selectedLanguage = "English";
                  });

                  Navigator.pop(context);
                },
              ),

              ListTile(
                leading: const Icon(Icons.translate),
                title: const Text("हिन्दी"),
                trailing: selectedLanguage == "हिन्दी"
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  setState(() {
                    selectedLanguage = "हिन्दी";
                  });

                  Navigator.pop(context);
                },
              ),

              const SizedBox(height: 25),
            ],
          ),
        );
      },
    );
  }

  Widget buildTile({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: Icon(icon, color: Colors.green.shade800),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: trailing ?? const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xffF6F8F5),

      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      body: ListView(
        children: [
          const SizedBox(height: 20),

          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 45,
                  backgroundColor: Colors.green.shade100,
                  backgroundImage: user?.photoURL != null
                      ? NetworkImage(user!.photoURL!)
                      : null,
                  child: user?.photoURL == null
                      ? const Icon(Icons.person, size: 45, color: Colors.green)
                      : null,
                ),

                const SizedBox(height: 12),

                Text(
                  user?.displayName ?? "Guest User",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),

                const SizedBox(height: 5),

                Text(
                  user?.email ?? "",
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 30),

          buildTile(
            icon: Icons.language,
            title: "Language",
            trailing: Text(
              selectedLanguage,
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            onTap: changeLanguage,
          ),

          buildTile(
            icon: Icons.dark_mode,
            title: "Dark Mode",
            trailing: Switch(
              value: darkMode,
              activeColor: Colors.green,
              onChanged: (value) {
                setState(() {
                  darkMode = value;
                });
              },
            ),
          ),

          buildTile(
            icon: Icons.info_outline,
            title: "About App",
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: "Ankur",
                applicationVersion: "1.0.0",
                applicationLegalese:
                    "AI Powered Paddy Seed Quality Assessment and Disease Detection System",
              );
            },
          ),

          buildTile(
            icon: Icons.privacy_tip,
            title: "Privacy Policy",
            onTap: () {},
          ),

          buildTile(
            icon: Icons.description,
            title: "Terms & Conditions",
            onTap: () {},
          ),

          buildTile(
            icon: Icons.logout,
            title: "Logout",
            trailing: const SizedBox(),
            onTap: logout,
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
