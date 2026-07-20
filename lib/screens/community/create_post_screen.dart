import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../models/community_post.dart';
import '../../services/community_service.dart';
import '../../services/story_service.dart';
import 'photo_editor_screen.dart';

enum CreatePostMode { post, story }

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, required this.mode, this.editingPost});

  final CreatePostMode mode;
  final CommunityPost? editingPost;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);

  final TextEditingController _captionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  File? _imageFile;
  Uint8List? _imageBytes;
  String _postType = 'general';
  bool _isSaving = false;

  final List<_PostTypeOption> _postTypes = const [
    _PostTypeOption('general', 'Update', Icons.forum_rounded),
    _PostTypeOption('meal', 'Meal', Icons.restaurant_rounded),
    _PostTypeOption('workout', 'Workout', Icons.fitness_center_rounded),
    _PostTypeOption('steps', 'Steps', Icons.directions_walk_rounded),
    _PostTypeOption('water', 'Water', Icons.water_drop_rounded),
    _PostTypeOption('streak', 'Streak', Icons.local_fire_department_rounded),
    _PostTypeOption('progress', 'Progress', Icons.trending_up_rounded),
  ];

  bool get _isStory => widget.mode == CreatePostMode.story;
  bool get _isEditing => widget.editingPost != null;

  @override
  void initState() {
    super.initState();

    final post = widget.editingPost;
    if (post != null) {
      _captionController.text = post.caption;
      _postType = post.type;
      if (post.imageBase64.isNotEmpty) {
        try {
          _imageBytes = base64Decode(post.imageBase64);
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 74,
      maxWidth: 1280,
      maxHeight: 1280,
    );

    if (picked == null) return;

    final file = File(picked.path);
    final bytes = await file.readAsBytes();
    final compressedBytes = _compressImageForFirestore(bytes);

    if (!mounted) return;

    setState(() {
      _imageFile = file;
      _imageBytes = compressedBytes;
    });
  }

  Future<void> _editPhoto() async {
    final bytes = _imageBytes;
    if (bytes == null) return;

    final edited = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => PhotoEditorScreen(imageBytes: bytes)),
    );

    if (edited == null) return;

    final compressedBytes = _compressImageForFirestore(edited);

    if (!mounted) return;
    setState(() {
      _imageBytes = compressedBytes;
    });
  }

  Uint8List _compressImageForFirestore(Uint8List inputBytes) {
    // Firestore documents have a 1 MiB limit. A full phone photo converted to
    // base64 can easily exceed that limit and Firestore returns
    // cloud_firestore/invalid-argument. Keep the encoded image safely below it.
    const int maxRawBytes = 620 * 1024;
    const int firstMaxSide = 1080;
    const int minMaxSide = 520;

    if (inputBytes.lengthInBytes <= maxRawBytes) {
      final decodedSmall = img.decodeImage(inputBytes);
      if (decodedSmall == null) return inputBytes;
    }

    final decoded = img.decodeImage(inputBytes);
    if (decoded == null) return inputBytes;

    img.Image working = img.bakeOrientation(decoded);
    var maxSide = firstMaxSide;

    Uint8List best = Uint8List.fromList(img.encodeJpg(working, quality: 72));

    while (true) {
      final width = working.width;
      final height = working.height;
      final longestSide = width > height ? width : height;

      img.Image resized = working;
      if (longestSide > maxSide) {
        resized = img.copyResize(
          working,
          width: width >= height ? maxSide : null,
          height: height > width ? maxSide : null,
          interpolation: img.Interpolation.average,
        );
      }

      for (final quality in const <int>[76, 68, 60, 52, 44, 36]) {
        final encoded = Uint8List.fromList(
          img.encodeJpg(resized, quality: quality),
        );
        best = encoded;
        if (encoded.lengthInBytes <= maxRawBytes) return encoded;
      }

      if (maxSide <= minMaxSide) return best;
      maxSide = (maxSide * 0.78).round();
      if (maxSide < minMaxSide) maxSide = minMaxSide;
    }
  }

  Future<void> _submit() async {
    if (_isSaving) return;

    final caption = _captionController.text.trim();

    if (_isStory && _imageBytes == null) {
      _showError('Please add an image for your story.');
      return;
    }

    if (!_isStory && caption.isEmpty && _imageBytes == null) {
      _showError('Write something or add a photo.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      String imageBase64 = '';

      if (_imageBytes != null) {
        final safeBytes = _compressImageForFirestore(_imageBytes!);
        imageBase64 = base64Encode(safeBytes);
      } else if (_imageFile != null) {
        final rawBytes = await _imageFile!.readAsBytes();
        final safeBytes = _compressImageForFirestore(rawBytes);
        imageBase64 = base64Encode(safeBytes);
      }

      if (_isStory) {
        await StoryService.createStory(
          imageBase64: imageBase64,
          caption: caption,
          type: _postType,
        );
      } else if (_isEditing) {
        await CommunityService.updatePost(
          postId: widget.editingPost!.id,
          type: _postType,
          caption: caption.isEmpty
              ? _defaultCaptionForType(_postType)
              : caption,
          imageBase64: imageBase64,
        );
      } else {
        await CommunityService.createPost(
          type: _postType,
          caption: caption.isEmpty
              ? _defaultCaptionForType(_postType)
              : caption,
          imageBase64: imageBase64,
          xp: _xpForType(_postType),
        );
      }

      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);

      final message = e.code == 'invalid-argument'
          ? 'Could not publish. The selected photo was too large for Firestore. Please pick it again and try.'
          : 'Could not publish: ${e.message ?? e.code}';
      _showError(message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('Could not publish: $e');
    }
  }

  String _defaultCaptionForType(String type) {
    switch (type) {
      case 'meal':
        return 'Logged a healthy meal today 🥗';
      case 'workout':
        return 'Workout completed 💪';
      case 'steps':
        return 'Step milestone completed 🔥';
      case 'water':
        return 'Hydration goal completed 💧';
      case 'streak':
        return 'Streak is still alive 🔥';
      case 'progress':
        return 'Progress update shared 📈';
      default:
        return 'NutriPulse update';
    }
  }

  int _xpForType(String type) {
    switch (type) {
      case 'meal':
        return 15;
      case 'workout':
        return 25;
      case 'steps':
        return 20;
      case 'water':
        return 15;
      case 'streak':
        return 40;
      case 'progress':
        return 30;
      default:
        return 10;
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.outfit()),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Uint8List? _previewBytes() => _imageBytes;

  @override
  Widget build(BuildContext context) {
    final title = _isEditing
        ? 'Edit Post'
        : (_isStory ? 'Create Story' : 'Create Post');

    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF253618), Color(0xFF0F140D), Color(0xFF070907)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _topBar(title),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _imagePickerCard(),
                      const SizedBox(height: 18),
                      if (!_isStory) ...[
                        _typeSelector(),
                        const SizedBox(height: 18),
                      ],
                      _captionBox(),
                    ],
                  ),
                ),
              ),
              _bottomPublishBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 18, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePickerCard() {
    final bytes = _previewBytes();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      height: _isStory ? 420 : 250,
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 26,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bytes != null)
              Container(
                color: Colors.black,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
              )
            else
              _emptyImageState(),

            if (bytes != null)
              Positioned(
                top: 14,
                right: 14,
                child: GestureDetector(
                  onTap: _editPhoto,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.auto_fix_high_rounded,
                          color: lime,
                          size: 17,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Edit',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: Row(
                children: [
                  Expanded(
                    child: _imageAction(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      onTap: () => _pickImage(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _imageAction(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      onTap: () => _pickImage(ImageSource.camera),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyImageState() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF202A19), Color(0xFF11170F)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isStory
                  ? Icons.auto_stories_rounded
                  : Icons.add_photo_alternate_rounded,
              color: lime,
              size: 44,
            ),
            const SizedBox(height: 10),
            Text(
              _isStory ? 'Add story image' : 'Add photo',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isStory
                  ? 'Stories disappear after 24 hours'
                  : 'Meal, workout, progress or achievement',
              style: GoogleFonts.outfit(
                color: soft,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.45),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: lime, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeSelector() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        itemCount: _postTypes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = _postTypes[index];
          final selected = _postType == item.type;

          return GestureDetector(
            onTap: () => setState(() => _postType = item.type),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? lime : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? lime : Colors.white.withOpacity(0.06),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    color: selected ? Colors.black : soft,
                    size: 17,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    item.label,
                    style: GoogleFonts.outfit(
                      color: selected ? Colors.black : soft,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _captionBox() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: TextField(
        controller: _captionController,
        maxLines: 6,
        minLines: 4,
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: _isStory
              ? 'Write a short story caption...'
              : 'Share your meal, milestone, workout or progress...',
          hintStyle: GoogleFonts.outfit(
            color: soft.withOpacity(0.72),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _bottomPublishBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).padding.bottom + 14,
      ),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.96),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: ElevatedButton(
          onPressed: _isSaving ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: lime,
            foregroundColor: Colors.black,
            disabledBackgroundColor: lime.withOpacity(0.35),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(21),
            ),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.black,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(
                  _isEditing
                      ? 'Save Changes'
                      : (_isStory ? 'Share Story' : 'Publish Post'),
                  style: GoogleFonts.outfit(
                    color: Colors.black,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ),
    );
  }
}

class _PostTypeOption {
  final String type;
  final String label;
  final IconData icon;

  const _PostTypeOption(this.type, this.label, this.icon);
}
