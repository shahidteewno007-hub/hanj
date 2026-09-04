import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/theme/app_theme.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _usernameController = TextEditingController();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  int _selectedColorIndex = 0;
  String? _selectedCharacterImage;
  String? _selectedAnimeTitle;
  List<Map<String, dynamic>> _characters = [];
  bool _isLoadingCharacters = false;

  // Avatar gradient presets
  static const _avatarGradients = [
    [Color(0xFF7C3AED), Color(0xFFE91E8C)],  // Purple-Pink (default)
    [Color(0xFF2196F3), Color(0xFF00BCD4)],  // Blue-Cyan
    [Color(0xFFFF6B35), Color(0xFFFF8E53)],  // Orange
    [Color(0xFF4CAF50), Color(0xFF8BC34A)],  // Green
    [Color(0xFFE91E63), Color(0xFFFF5722)],  // Pink-Red
    [Color(0xFF9C27B0), Color(0xFF3F51B5)],  // Purple-Indigo
    [Color(0xFF00BCD4), Color(0xFF4CAF50)],  // Cyan-Green
    [Color(0xFFFF9800), Color(0xFFFFEB3B)],  // Orange-Yellow
  ];

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) {
      _usernameController.text = user.displayName ?? '';
    }
    _loadSavedColor();
    _loadCharacters();
  }

  Future<void> _loadSavedColor() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists && mounted) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _selectedColorIndex = (data['avatarColorIndex'] as int?) ?? 0;
        _selectedCharacterImage = data['avatarImageUrl'] as String?;
      });
    }
  }

  Future<void> _loadCharacters() async {
    // No longer auto-loads — user picks anime via _showAnimePicker
  }

  Future<void> _loadCharactersForAnime(String animeId, String animeTitle) async {
    setState(() { _isLoadingCharacters = true; _characters = []; _selectedAnimeTitle = animeTitle; });
    try {
      final response = await http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {'Content-Type': 'application/json', 'User-Agent': 'Aruku/1.0'},
        body: jsonEncode({
          'query': r'''
          query($id: Int) {
            Media(id: $id, type: ANIME) {
              characters(perPage: 20, sort: ROLE) {
                nodes {
                  name { full }
                  image { medium }
                }
              }
            }
          }''',
          'variables': {'id': int.tryParse(animeId) ?? 0},
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final nodes = data['data']['Media']['characters']['nodes'] as List;
        final chars = nodes
            .where((n) => n['image']['medium'] != null)
            .map((n) => {
              'name': n['name']['full'] as String? ?? '',
              'image': n['image']['medium'] as String,
            })
            .toList();
        if (mounted) setState(() { _characters = chars; _isLoadingCharacters = false; });
      } else {
        if (mounted) setState(() => _isLoadingCharacters = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingCharacters = false);
    }
  }

  void _showAnimePicker(BuildContext context) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final snapshot = await _firestore
        .collection('users').doc(uid).collection('animeList')
        .orderBy('addedAt', descending: true)
        .limit(50)
        .get();

    if (!mounted) return;

    final animeList = snapshot.docs.map((d) {
      final data = d.data();
      return {
        'id':       data['animeId']?.toString() ?? '',
        'title':    data['title'] as String? ?? 'Unknown',
        'imageUrl': data['imageUrl'] as String?,
      };
    }).where((a) => a['id']!.isNotEmpty).toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnimePickerSheet(
        animeList: animeList,
        onSelected: (id, title) {
          Navigator.pop(context);
          _loadCharactersForAnime(id, title);
        },
      ),
    );
  }

  Future<void> _saveProfile() async {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username cannot be empty')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = _auth.currentUser;
      if (user != null) {
        // Update display name in Firebase Auth
        await user.updateDisplayName(username);

        // Save avatar color preference to Firestore
        await _firestore.collection('users').doc(user.uid).set({
          'displayName': username,
          'avatarColorIndex': _selectedColorIndex,
          'avatarImageUrl': _selectedCharacterImage,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated!'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    final initial =
        (_usernameController.text.isNotEmpty
            ? _usernameController.text[0]
            : user?.email?[0] ?? 'A')
            .toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveProfile,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primary),
                  )
                : const Text('Save',
                    style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 16),

            // Avatar preview
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: _selectedCharacterImage == null ? LinearGradient(
                  colors: _avatarGradients[_selectedColorIndex],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ) : null,
                color: _selectedCharacterImage != null ? Colors.black : null,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: _avatarGradients[_selectedColorIndex][0]
                        .withValues(alpha: 0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: _selectedCharacterImage != null
                    ? Image.network(_selectedCharacterImage!, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(child: Text(initial,
                          style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold))))
                    : Center(child: Text(initial,
                        style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.bold))),
              ),
            ),

            const SizedBox(height: 16),

            // Character picker
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Pick a Character',
                  style: AppTheme.serif(fontSize: 16, weight: FontWeight.w600)),
            ),
            const SizedBox(height: 4),
            Text(
              'Search your list and pick a character as your avatar',
              style: AppTheme.sans(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 12),

            // Search bar for anime
            GestureDetector(
              onTap: () => _showAnimePicker(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        color: AppTheme.textMuted, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      _selectedAnimeTitle ?? 'Search your anime list...',
                      style: AppTheme.sans(
                          fontSize: 14,
                          color: _selectedAnimeTitle != null
                              ? AppTheme.textPrimary
                              : AppTheme.textMuted),
                    ),
                    const Spacer(),
                    if (_selectedAnimeTitle != null)
                      GestureDetector(
                        onTap: () => setState(() {
                          _selectedAnimeTitle = null;
                          _characters = [];
                          _selectedCharacterImage = null;
                        }),
                        child: const Icon(Icons.close_rounded,
                            color: AppTheme.textMuted, size: 16),
                      )
                    else
                      const Icon(Icons.chevron_right_rounded,
                          color: AppTheme.textMuted, size: 16),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Characters
            if (_isLoadingCharacters)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(
                    color: AppTheme.primary, strokeWidth: 2)),
              )
            else if (_characters.isNotEmpty) ...[
              SizedBox(
                height: 110,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _characters.length,
                  itemBuilder: (context, i) {
                    final char = _characters[i];
                    final imgUrl = char['image'] as String;
                    final isSelected = _selectedCharacterImage == imgUrl;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedCharacterImage = imgUrl),
                      child: Container(
                        width: 72,
                        margin: const EdgeInsets.only(right: 10),
                        child: Column(
                          children: [
                            Container(
                              width: 72,
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.primary
                                      : AppTheme.cardBorder,
                                  width: isSelected ? 2.5 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CachedNetworkImage(
                                      imageUrl: imgUrl,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          const Icon(Icons.person),
                                    ),
                                    if (isSelected)
                                      Container(
                                        color: AppTheme.primary.withValues(alpha: 0.35),
                                        child: const Icon(Icons.check_rounded,
                                            color: Colors.white),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              char['name'] as String? ?? '',
                              style: AppTheme.sans(fontSize: 9,
                                  color: AppTheme.textMuted),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ] else if (_selectedAnimeTitle != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text('No characters found for this anime',
                    style: AppTheme.sans(color: AppTheme.textMuted, fontSize: 13)),
              ),
            ],

            const SizedBox(height: 8),
            Text(
              'Or choose avatar color',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textMuted),
            ),

            const SizedBox(height: 16),

            // Color picker grid
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: List.generate(_avatarGradients.length, (i) {
                final isSelected = _selectedColorIndex == i;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColorIndex = i),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _avatarGradients[i],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: _avatarGradients[i][0]
                                      .withValues(alpha: 0.5),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                )
                              ]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 22)
                          : null,
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 36),

            // Username field
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Username',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _usernameController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Your display name',
                prefixIcon: const Icon(Icons.person_outline_rounded),
                filled: true,
                fillColor: AppTheme.surfaceLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Email (read only)
            Align(
              alignment: Alignment.centerLeft,
              child:
                  Text('Email', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.email_outlined,
                      color: AppTheme.textMuted, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      user?.email ?? '',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Verified',
                      style:
                          TextStyle(color: AppTheme.success, fontSize: 12)),
                ],
              ),
            ),

            const SizedBox(height: 40),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                child: _isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Anime Picker Sheet
// ─────────────────────────────────────────────────────────────

class _AnimePickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> animeList;
  final void Function(String id, String title) onSelected;

  const _AnimePickerSheet({
    required this.animeList,
    required this.onSelected,
  });

  @override
  State<_AnimePickerSheet> createState() => _AnimePickerSheetState();
}

class _AnimePickerSheetState extends State<_AnimePickerSheet> {
  String _search = '';

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return widget.animeList;
    return widget.animeList
        .where((a) => (a['title'] as String)
            .toLowerCase()
            .contains(_search.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF110C08),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text('Pick an Anime',
                    style: AppTheme.serif(
                        fontSize: 18, weight: FontWeight.w700)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close_rounded,
                      color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _search = v),
              style: AppTheme.sans(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search your list...',
                hintStyle: AppTheme.sans(
                    color: AppTheme.textMuted, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.textMuted, size: 18),
                filled: true,
                fillColor: AppTheme.surfaceLight,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text('No anime found',
                        style: AppTheme.sans(
                            color: AppTheme.textMuted)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final anime = _filtered[i];
                      final title = anime['title'] as String;
                      final imageUrl = anime['imageUrl'] as String?;
                      final id = anime['id'] as String;

                      return GestureDetector(
                        onTap: () => widget.onSelected(id, title),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.cardBorder),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: imageUrl != null
                                    ? Image.network(
                                        imageUrl,
                                        width: 44,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            Container(
                                          width: 44,
                                          height: 60,
                                          color: AppTheme.surface,
                                        ),
                                      )
                                    : Container(
                                        width: 44,
                                        height: 60,
                                        color: AppTheme.surface,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(title,
                                    style: AppTheme.sans(
                                        fontSize: 14,
                                        weight: FontWeight.w500)),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: AppTheme.textMuted, size: 18),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
