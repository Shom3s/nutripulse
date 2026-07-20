import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';

class PhotoEditorScreen extends StatefulWidget {
  const PhotoEditorScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<PhotoEditorScreen> createState() => _PhotoEditorScreenState();
}

class _PhotoEditorScreenState extends State<PhotoEditorScreen> {
  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color soft = Color(0xFFB7C2A8);

  final GlobalKey _captureKey = GlobalKey();
  final TextEditingController _textCtrl = TextEditingController();

  Offset _textOffset = const Offset(42, 180);
  String _overlayText = '';
  double _fontSize = 28;
  int _selectedFilter = 0;

  final List<String> _emojis = const [
    '🔥',
    '💪',
    '🥗',
    '❤️',
    '⭐',
    '🏆',
    '😮',
    '👏',
  ];

  final List<_EditorSticker> _stickers = [];

  final List<List<double>> _filters = const [
    // Normal
    <double>[1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0],

    // Bright
    <double>[
      1.15,
      0,
      0,
      0,
      12,
      0,
      1.15,
      0,
      0,
      12,
      0,
      0,
      1.15,
      0,
      12,
      0,
      0,
      0,
      1,
      0,
    ],

    // Warm
    <double>[
      1.15,
      0,
      0,
      0,
      8,
      0,
      1.05,
      0,
      0,
      4,
      0,
      0,
      0.90,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ],

    // Cool
    <double>[
      0.90,
      0,
      0,
      0,
      0,
      0,
      1.02,
      0,
      0,
      2,
      0,
      0,
      1.18,
      0,
      10,
      0,
      0,
      0,
      1,
      0,
    ],

    // Pop / Contrast
    <double>[
      1.25,
      0,
      0,
      0,
      -15,
      0,
      1.25,
      0,
      0,
      -15,
      0,
      0,
      1.25,
      0,
      -15,
      0,
      0,
      0,
      1,
      0,
    ],
  ];

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      final renderObject = _captureKey.currentContext?.findRenderObject();

      if (renderObject is! RenderRepaintBoundary) {
        Navigator.pop(context, widget.imageBytes);
        return;
      }

      final image = await renderObject.toImage(pixelRatio: 2.6);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();

      if (!mounted) return;
      Navigator.pop(context, bytes ?? widget.imageBytes);
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context, widget.imageBytes);
    }
  }

  void _addEmoji(String emoji) {
    setState(() {
      _stickers.add(
        _EditorSticker(text: emoji, offset: const Offset(90, 180), size: 38),
      );
    });
  }

  void _removeSticker(int index) {
    setState(() {
      if (index >= 0 && index < _stickers.length) {
        _stickers.removeAt(index);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: RepaintBoundary(
                    key: _captureKey,
                    child: Container(
                      color: Colors.black,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColorFiltered(
                            colorFilter: ColorFilter.matrix(
                              _filters[_selectedFilter],
                            ),
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 4,
                              clipBehavior: Clip.none,
                              child: Image.memory(
                                widget.imageBytes,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),

                          if (_overlayText.trim().isNotEmpty)
                            Positioned(
                              left: _textOffset.dx,
                              top: _textOffset.dy,
                              child: GestureDetector(
                                onPanUpdate: (details) {
                                  setState(() {
                                    _textOffset += details.delta;
                                  });
                                },
                                child: Text(
                                  _overlayText,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: _fontSize,
                                    fontWeight: FontWeight.w900,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                          for (int i = 0; i < _stickers.length; i++)
                            Positioned(
                              left: _stickers[i].offset.dx,
                              top: _stickers[i].offset.dy,
                              child: GestureDetector(
                                onPanUpdate: (details) {
                                  setState(() {
                                    _stickers[i].offset += details.delta;
                                  });
                                },
                                onLongPress: () => _removeSticker(i),
                                child: Text(
                                  _stickers[i].text,
                                  style: TextStyle(
                                    fontSize: _stickers[i].size,
                                    shadows: const [
                                      Shadow(
                                        color: Colors.black,
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _editorBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context, widget.imageBytes),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(
              'Edit Photo',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          TextButton(
            onPressed: _save,
            child: Text(
              'Done',
              style: GoogleFonts.outfit(
                color: lime,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editorBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF10150D),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Pinch to crop • Drag text/emoji • Long press emoji to remove',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _textCtrl,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            onChanged: (v) => setState(() => _overlayText = v),
            decoration: InputDecoration(
              hintText: 'Add text...',
              hintStyle: GoogleFonts.outfit(color: soft),
              filled: true,
              fillColor: Colors.white.withOpacity(0.07),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide.none,
              ),
              prefixIcon: const Icon(Icons.text_fields_rounded, color: lime),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _emojis.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final emoji = _emojis[index];

                return GestureDetector(
                  onTap: () => _addEmoji(emoji),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Center(
                      child: Text(emoji, style: const TextStyle(fontSize: 21)),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: List.generate(5, (index) {
                final labels = ['Normal', 'Bright', 'Warm', 'Cool', 'Pop'];
                final selected = _selectedFilter == index;

                return GestureDetector(
                  onTap: () => setState(() => _selectedFilter = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: selected ? lime : Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: selected ? lime : Colors.white.withOpacity(0.07),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      labels[index],
                      style: GoogleFonts.outfit(
                        color: selected ? Colors.black : soft,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Text size',
                style: GoogleFonts.outfit(
                  color: soft,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 18,
                  max: 48,
                  activeColor: lime,
                  inactiveColor: Colors.white.withOpacity(0.12),
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditorSticker {
  _EditorSticker({
    required this.text,
    required this.offset,
    required this.size,
  });

  String text;
  Offset offset;
  double size;
}
