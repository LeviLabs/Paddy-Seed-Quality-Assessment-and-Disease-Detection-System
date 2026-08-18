import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'login_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  // Use this if your HomeScreen opens the profile as a bottom sheet.
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.50,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return _ProfileContent(
              scrollController: scrollController,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: _ProfileContent(),
    );
  }
}

class _ProfileContent extends StatefulWidget {
  final ScrollController? scrollController;

  const _ProfileContent({
    this.scrollController,
  });

  @override
  State<_ProfileContent> createState() =>
      _ProfileContentState();
}

class _ProfileContentState
    extends State<_ProfileContent> {
  bool _isDeletingAccount = false;
  bool _isSigningOut = false;
  bool _isSavingName = false;

  // ============================================================
  // LANGUAGES
  // ============================================================

  final List<Map<String, String>> _languages = [
    {
      'code': 'en',
      'name': 'English',
    },
    {
      'code': 'hi',
      'name': 'Hindi',
    },
    {
      'code': 'ta',
      'name': 'Tamil',
    },
    {
      'code': 'te',
      'name': 'Telugu',
    },
    {
      'code': 'mr',
      'name': 'Marathi',
    },
    {
      'code': 'bn',
      'name': 'Bengali',
    },
  ];

  // ============================================================
  // USER
  // ============================================================

  User? get _currentUser {
    return FirebaseAuth.instance.currentUser;
  }

  // ============================================================
  // SIGN OUT
  // ============================================================

  Future<void> _signOut() async {
    if (_isSigningOut) return;

    setState(() {
      _isSigningOut = true;
    });

    try {
      // Sign out from Google.
      try {
        final GoogleSignIn googleSignIn =
            GoogleSignIn();

        await googleSignIn.signOut();
      } catch (e) {
        debugPrint(
          'Google sign out error: $e',
        );
      }

      // Sign out from Firebase.
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // IMPORTANT:
      // LoginPage is the actual login widget.
      //
      // pushAndRemoveUntil removes Home/Profile/etc.
      // from the navigation stack.
      Navigator.of(
        context,
        rootNavigator: true,
      ).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginPage(),
        ),
        (route) => false,
      );
    } catch (e) {
      debugPrint(
        'Sign out error: $e',
      );

      if (!mounted) return;

      setState(() {
        _isSigningOut = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to sign out. Please try again.',
          ),
        ),
      );
    }
  }

  // ============================================================
  // DELETE FIRESTORE USER DATA
  // ============================================================

  Future<void> _deleteFirestoreUserData(
    String uid,
  ) async {
    final FirebaseFirestore firestore =
        FirebaseFirestore.instance;

    final DocumentReference<Map<String, dynamic>>
        userRef = firestore
        .collection('users')
        .doc(uid);

    // ------------------------------------------------------------
    // Delete tests subcollection
    // ------------------------------------------------------------

    final QuerySnapshot<Map<String, dynamic>>
        testsSnapshot =
        await userRef
            .collection('tests')
            .get();

    if (testsSnapshot.docs.isNotEmpty) {
      final WriteBatch batch =
          firestore.batch();

      for (final doc in testsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    }

    // ------------------------------------------------------------
    // Delete main user document
    // ------------------------------------------------------------

    await userRef.delete();
  }

  // ============================================================
  // DELETE ACCOUNT
  // ============================================================

  Future<void> _deleteAccount() async {
    if (_isDeletingAccount) return;

    final User? user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No logged-in account found.',
          ),
        ),
      );

      return;
    }

    // ------------------------------------------------------------
    // CONFIRMATION DIALOG
    // ------------------------------------------------------------

    final bool? confirmed =
        await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Delete Account?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'This will permanently delete your account '
            'and your saved data. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop(false);
              },
              child: const Text(
                'Cancel',
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop(true);
              },
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isDeletingAccount = true;
    });

    try {
      final String uid = user.uid;

      // ----------------------------------------------------------
      // 1. Delete Firestore data
      // ----------------------------------------------------------

      await _deleteFirestoreUserData(uid);

      // ----------------------------------------------------------
      // 2. Delete Firebase Authentication account
      // ----------------------------------------------------------

      try {
        await user.delete();
      } on FirebaseAuthException catch (e) {
        // Firebase may require recent authentication.
        if (e.code ==
            'requires-recent-login') {
          if (mounted) {
            setState(() {
              _isDeletingAccount = false;
            });

            ScaffoldMessenger.of(context)
                .showSnackBar(
              const SnackBar(
                content: Text(
                  'For security, please sign in again before deleting your account.',
                ),
              ),
            );
          }

          return;
        }

        rethrow;
      }

      // ----------------------------------------------------------
      // 3. Google sign out
      // ----------------------------------------------------------

      try {
        final GoogleSignIn googleSignIn =
            GoogleSignIn();

        await googleSignIn.signOut();
      } catch (e) {
        debugPrint(
          'Google sign out after delete: $e',
        );
      }

      if (!mounted) return;

      // ----------------------------------------------------------
      // 4. Go to LoginPage
      // ----------------------------------------------------------

      Navigator.of(
        context,
        rootNavigator: true,
      ).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginPage(),
        ),
        (route) => false,
      );
    } catch (e) {
      debugPrint(
        'Delete account error: $e',
      );

      if (!mounted) return;

      setState(() {
        _isDeletingAccount = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to delete account.\n$e',
          ),
        ),
      );
    }
  }

  // ============================================================
  // CHANGE USERNAME
  // ============================================================

  Future<void> _changeUsername(
    String currentName,
  ) async {
    final User? user =
        FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final TextEditingController controller =
        TextEditingController(
      text: currentName,
    );

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: const Text(
                'Change Username',
              ),
              content: TextField(
                controller: controller,
                autofocus: true,
                decoration:
                    const InputDecoration(
                  hintText:
                      'Enter username',
                  border:
                      OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      _isSavingName
                          ? null
                          : () {
                              Navigator.of(
                                dialogContext,
                              ).pop();
                            },
                  child: const Text(
                    'Cancel',
                  ),
                ),
                ElevatedButton(
                  onPressed:
                      _isSavingName
                          ? null
                          : () async {
                              final String
                                  newName =
                                  controller
                                      .text
                                      .trim();

                              if (newName
                                  .isEmpty) {
                                ScaffoldMessenger
                                    .of(
                                  context,
                                ).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text(
                                      'Username cannot be empty.',
                                    ),
                                  ),
                                );
                                return;
                              }

                              if (newName ==
                                  currentName) {
                                Navigator.of(
                                  dialogContext,
                                ).pop();
                                return;
                              }

                              setDialogState(
                                () {
                                  _isSavingName =
                                      true;
                                },
                              );

                              try {
                                await FirebaseFirestore
                                    .instance
                                    .collection(
                                      'users',
                                    )
                                    .doc(
                                      user.uid,
                                    )
                                    .set(
                                  {
                                    'name':
                                        newName,
                                    'updatedAt':
                                        FieldValue
                                            .serverTimestamp(),
                                  },
                                  SetOptions(
                                    merge:
                                        true,
                                  ),
                                );

                                await user
                                    .updateDisplayName(
                                  newName,
                                );

                                if (!mounted) {
                                  return;
                                }

                                Navigator.of(
                                  dialogContext,
                                ).pop();

                                setState(() {});
                              } catch (e) {
                                debugPrint(
                                  'Username update error: $e',
                                );

                                setDialogState(
                                  () {
                                    _isSavingName =
                                        false;
                                  },
                                );

                                ScaffoldMessenger
                                    .of(
                                  context,
                                ).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text(
                                      'Unable to update username.',
                                    ),
                                  ),
                                );
                              }
                            },
                  child: _isSavingName
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child:
                              CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Save',
                        ),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  // ============================================================
  // CHANGE LANGUAGE
  // ============================================================

  Future<void> _changeLanguage(
    String currentLanguage,
  ) async {
    final User? user =
        FirebaseAuth.instance.currentUser;

    if (user == null) return;

    await showModalBottomSheet(
      context: context,
      shape:
          const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(
              vertical: 12,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const Padding(
                  padding:
                      EdgeInsets.all(16),
                  child: Align(
                    alignment:
                        Alignment.centerLeft,
                    child: Text(
                      'Select Language',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                ..._languages.map(
                  (language) {
                    final String code =
                        language['code']!;

                    final String name =
                        language['name']!;

                    final bool selected =
                        code ==
                            currentLanguage;

                    return ListTile(
                      title: Text(name),
                      trailing: selected
                          ? const Icon(
                              Icons
                                  .check_circle,
                              color:
                                  Colors.green,
                            )
                          : null,
                      onTap: () async {
                        try {
                          await FirebaseFirestore
                              .instance
                              .collection(
                                'users',
                              )
                              .doc(
                                user.uid,
                              )
                              .set(
                            {
                              'language':
                                  code,
                              'languageSelected':
                                  true,
                              'updatedAt':
                                  FieldValue
                                      .serverTimestamp(),
                            },
                            SetOptions(
                              merge: true,
                            ),
                          );

                          if (sheetContext
                              .mounted) {
                            Navigator.of(
                              sheetContext,
                            ).pop();
                          }

                          if (mounted) {
                            setState(() {});
                          }
                        } catch (e) {
                          debugPrint(
                            'Language update error: $e',
                          );
                        }
                      },
                    );
                  },
                ),

                const SizedBox(
                  height: 12,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // TEST COUNT
  // ============================================================

  Widget _buildTestCount(User? user) {
    if (user == null) {
      return _buildTestCountContainer(
        0,
      );
    }

    return StreamBuilder<
        QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('tests')
          .snapshots(),
      builder: (
        context,
        snapshot,
      ) {
        int count = 0;

        if (snapshot.hasData) {
          count =
              snapshot.data!.docs.length;
        }

        return _buildTestCountContainer(
          count,
        );
      },
    );
  }

  Widget _buildTestCountContainer(
    int count,
  ) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(
        vertical: 22,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 32,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 4,
          ),
          Text(
            'Total Tests',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PROFILE AVATAR
  // ============================================================

  Widget _buildAvatar(
    User? user,
    String name,
  ) {
    final String photoUrl =
        user?.photoURL ?? '';

    if (photoUrl.isNotEmpty) {
      return Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.grey.shade300,
            width: 2,
          ),
          image: DecorationImage(
            image: NetworkImage(
              photoUrl,
            ),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    String initial = '?';

    if (name.trim().isNotEmpty) {
      initial =
          name.trim()[0].toUpperCase();
    }

    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue.shade400,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 30,
            color: Colors.white,
            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final User? user =
        FirebaseAuth.instance.currentUser;

    final Widget content =
        _buildProfileContent(user);

    if (widget.scrollController != null) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: content,
      ),
    );
  }

  // ============================================================
  // PROFILE CONTENT
  // ============================================================

  Widget _buildProfileContent(
    User? user,
  ) {
    if (user == null) {
      return _buildLoggedOutView();
    }

    return StreamBuilder<
        DocumentSnapshot<
            Map<String, dynamic>>>(
      stream: FirebaseFirestore
          .instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (
        context,
        snapshot,
      ) {
        final Map<String, dynamic>? data =
            snapshot.data?.data();

        final String name =
            (data?['name'] as String?)
                    ?.trim()
                    .isNotEmpty ==
                true
            ? (data!['name'] as String)
            : (user.displayName ??
                'User');

        final String email =
            user.email ?? '';

        final String language =
            (data?['language']
                    as String?) ??
                'en';

        final String languageName =
            _languages.firstWhere(
          (item) =>
              item['code'] == language,
          orElse: () => {
            'code': 'en',
            'name': 'English',
          },
        )['name']!;

        return ListView(
          controller:
              widget.scrollController,
          padding:
              const EdgeInsets.fromLTRB(
            20,
            12,
            20,
            40,
          ),
          children: [
            // ------------------------------------------------------
            // HANDLE
            // ------------------------------------------------------

            if (widget.scrollController !=
                null)
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin:
                      const EdgeInsets.only(
                    bottom: 18,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        Colors.grey.shade300,
                    borderRadius:
                        BorderRadius.circular(
                      10,
                    ),
                  ),
                ),
              ),

            // ------------------------------------------------------
            // HEADER
            // ------------------------------------------------------

            Row(
              children: [
                if (widget.scrollController !=
                    null)
                  IconButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                      );
                    },
                    icon: const Icon(
                      Icons
                          .arrow_back_ios_new,
                    ),
                  ),

                const Spacer(),

                const Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),

                const Spacer(),

                if (widget.scrollController !=
                    null)
                  const SizedBox(
                    width: 48,
                  ),
              ],
            ),

            const SizedBox(
              height: 28,
            ),

            // ------------------------------------------------------
            // PROFILE HEADER
            // ------------------------------------------------------

            Center(
              child: Column(
                children: [
                  _buildAvatar(
                    user,
                    name,
                  ),

                  const SizedBox(
                    height: 14,
                  ),

                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          textAlign:
                              TextAlign.center,
                          overflow:
                              TextOverflow.ellipsis,
                          style:
                              const TextStyle(
                            fontSize: 23,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      GestureDetector(
                        onTap: () {
                          _changeUsername(
                            name,
                          );
                        },
                        child:
                            const Icon(
                          Icons.edit_rounded,
                          size: 19,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(
                    height: 6,
                  ),

                  Text(
                    email,
                    textAlign:
                        TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey
                          .shade600,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 30,
            ),

            // ------------------------------------------------------
            // TOTAL TESTS
            // ------------------------------------------------------

            _buildTestCount(user),

            const SizedBox(
              height: 20,
            ),

            // ------------------------------------------------------
            // LANGUAGE
            // ------------------------------------------------------

            _buildSettingsCard(
              icon: Icons.language_rounded,
              title: 'Language',
              subtitle:
                  'Dataset language: $languageName',
              onTap: () {
                _changeLanguage(
                  language,
                );
              },
            ),

            const SizedBox(
              height: 20,
            ),

            // ------------------------------------------------------
            // ACCOUNT ACTIONS
            // ------------------------------------------------------

            Container(
              decoration: BoxDecoration(
                color:
                    const Color(0xFFF7F7F7),
                borderRadius:
                    BorderRadius.circular(
                  18,
                ),
              ),
              child: Column(
                children: [
                  // DELETE ACCOUNT
                  ListTile(
                    contentPadding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: _isDeletingAccount
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.red,
                            ),
                          )
                        : const Icon(
                            Icons
                                .delete_outline_rounded,
                            color: Colors.red,
                          ),
                    title: Text(
                      _isDeletingAccount
                          ? 'Deleting Account...'
                          : 'Delete Account',
                      style: const TextStyle(
                        fontWeight:
                            FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                    subtitle:
                        const Text(
                      'Permanently delete your account and data',
                      style: TextStyle(
                        fontSize: 12,
                      ),
                    ),
                    onTap:
                        _isDeletingAccount
                            ? null
                            : _deleteAccount,
                  ),

                  Divider(
                    height: 1,
                    indent: 18,
                    endIndent: 18,
                    color:
                        Colors.grey.shade300,
                  ),

                  // SIGN OUT
                  ListTile(
                    contentPadding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 18,
                      vertical: 4,
                    ),
                    leading: _isSigningOut
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons
                                .logout_rounded,
                            color: Colors.black,
                          ),
                    title: const Text(
                      'Sign Out',
                      style: TextStyle(
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                    subtitle:
                        const Text(
                      'Sign out of this account',
                      style: TextStyle(
                        fontSize: 12,
                      ),
                    ),
                    onTap:
                        _isSigningOut
                            ? null
                            : _signOut,
                  ),
                ],
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            // ------------------------------------------------------
            // DELETE ACCOUNT INFORMATION
            // ------------------------------------------------------

            Text(
              'Deleting your account removes your Firebase '
              'authentication account and saved profile/test data.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // SETTINGS CARD
  // ============================================================

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(18),
      child: Container(
        padding:
            const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color:
              const Color(0xFFF7F7F7),
          borderRadius:
              BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                color:
                    Colors.blue.shade50,
                borderRadius:
                    BorderRadius.circular(
                  14,
                ),
              ),
              child: Icon(
                icon,
                color:
                    Colors.blue.shade600,
                size: 27,
              ),
            ),

            const SizedBox(
              width: 15,
            ),

            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    title,
                    style:
                        const TextStyle(
                      fontSize: 17,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  const SizedBox(
                    height: 4,
                  ),

                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey
                          .shade600,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(
              Icons
                  .chevron_right_rounded,
              size: 28,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // LOGGED OUT VIEW
  // ============================================================

  Widget _buildLoggedOutView() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.person_outline,
              size: 70,
              color: Colors.grey,
            ),

            const SizedBox(
              height: 20,
            ),

            const Text(
              'You are not signed in',
              style: TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 20,
            ),

            ElevatedButton(
              onPressed: () {
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) =>
                        const LoginPage(),
                  ),
                  (route) => false,
                );
              },
              child: const Text(
                'Go to Login',
              ),
            ),
          ],
        ),
      ),
    );
  }
}