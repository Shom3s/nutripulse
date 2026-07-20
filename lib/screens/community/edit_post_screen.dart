import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/community_post.dart';
import '../../services/community_service.dart';

class EditPostScreen extends StatefulWidget {
  const EditPostScreen({super.key, required this.post});

  final CommunityPost post;

  @override
  State<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends State<EditPostScreen> {
  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color soft = Color(0xFFB7C2A8);

  late final TextEditingController captionCtrl;
  late String type;
  bool saving = false;

  final types = const [
    'general',
    'meal',
    'workout',
    'steps',
    'water',
    'streak',
    'progress',
  ];

  @override
  void initState() {
    super.initState();
    captionCtrl = TextEditingController(text: widget.post.caption);
    type = widget.post.type;
  }

  @override
  void dispose() {
    captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (saving) return;

    setState(() => saving = true);

    try {
      await CommunityService.updatePost(
        postId: widget.post.id,
        caption: captionCtrl.text,
        type: type,
      );

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update post: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF253618), Color(0xFF0F140D), Color(0xFF070907)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _typeSelector(),
                      const SizedBox(height: 18),
                      _captionBox(),
                    ],
                  ),
                ),
              ),
              _saveBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 18, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(
              'Edit Post',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeSelector() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        physics: const BouncingScrollPhysics(),
        scrollDirection: Axis.horizontal,
        itemCount: types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final item = types[index];
          final selected = type == item;

          return GestureDetector(
            onTap: () => setState(() => type = item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: selected ? lime : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? lime : Colors.white.withOpacity(0.06),
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                item[0].toUpperCase() + item.substring(1),
                style: GoogleFonts.outfit(
                  color: selected ? Colors.black : soft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
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
        controller: captionCtrl,
        maxLines: 8,
        minLines: 5,
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: 'Update your caption...',
          hintStyle: GoogleFonts.outfit(
            color: soft.withOpacity(0.72),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _saveBar() {
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
        height: 56,
        child: ElevatedButton(
          onPressed: saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: lime,
            foregroundColor: Colors.black,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: saving
              ? const CircularProgressIndicator(color: Colors.black)
              : Text(
                  'Save Changes',
                  style: GoogleFonts.outfit(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ),
    );
  }
}
