import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/market_item.dart';
import '../../../services/market_service.dart';

class AddMarketItemScreen extends StatefulWidget {
  const AddMarketItemScreen({super.key, this.editItem});

  final MarketItem? editItem;

  bool get isEditing => editItem != null;

  @override
  State<AddMarketItemScreen> createState() => _AddMarketItemScreenState();
}

class _AddMarketItemScreenState extends State<AddMarketItemScreen>
    with AutomaticKeepAliveClientMixin {
  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color card2 = Color(0xFF23291F);
  static const Color soft = Color(0xFFB7C2A8);

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _locationCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();

  String _category = 'Fruits';
  String _imageBase64 = '';
  bool _saving = false;

  static const List<_MarketCategory> _categories = [
    _MarketCategory('Fruits', Icons.eco_rounded),
    _MarketCategory('Homemade', Icons.rice_bowl_rounded),
    _MarketCategory('Protein', Icons.fitness_center_rounded),
    _MarketCategory('Drinks', Icons.local_drink_rounded),
    _MarketCategory('Snacks', Icons.cookie_rounded),
  ];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final item = widget.editItem;
    if (item != null) {
      _nameCtrl.text = item.name;
      _descCtrl.text = item.description;
      _priceCtrl.text = item.price.toStringAsFixed(2);
      _qtyCtrl.text = item.quantity.toString();
      _locationCtrl.text = item.location;
      _expiryCtrl.text = item.expiryDate;
      _imageBase64 = item.imageBase64;

      final labels = _categories.map((category) => category.label).toSet();
      _category = labels.contains(item.category) ? item.category : 'Fruits';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _locationCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    FocusScope.of(context).unfocus();
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 52,
      maxWidth: 720,
    );
    if (picked == null) return;

    final encoded = await MarketService.imageFileToBase64(File(picked.path));
    if (!mounted) return;
    setState(() => _imageBase64 = encoded);
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    final name = _nameCtrl.text.trim();
    final location = _locationCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;

    if (name.isEmpty || location.isEmpty || price <= 0 || qty <= 0) {
      HapticFeedback.selectionClick();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please fill food name, valid price, quantity and pickup location.',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    HapticFeedback.lightImpact();
    setState(() => _saving = true);

    try {
      if (widget.isEditing) {
        await MarketService.updateItem(
          item: widget.editItem!,
          name: name,
          description: _descCtrl.text,
          category: _category,
          price: price,
          quantity: qty,
          location: location,
          expiryDate: _expiryCtrl.text,
          imageBase64: _imageBase64,
        );
      } else {
        await MarketService.createItem(
          name: name,
          description: _descCtrl.text,
          category: _category,
          price: price,
          quantity: qty,
          location: location,
          expiryDate: _expiryCtrl.text,
          imageBase64: _imageBase64,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing ? 'Food listing updated' : 'Food listing posted',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
          ),
          backgroundColor: card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? 'Could not update listing: $e'
                : 'Could not post listing: $e',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF263919), bg, Color(0xFF060806)],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            cacheExtent: 360,
            slivers: [
              SliverToBoxAdapter(child: RepaintBoundary(child: _topBar())),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate.fixed([
                    RepaintBoundary(child: _heroCard()),
                    const SizedBox(height: 16),
                    RepaintBoundary(child: _photoPicker()),
                    const SizedBox(height: 18),
                    _input(
                      'Food name',
                      _nameCtrl,
                      Icons.restaurant_rounded,
                      hint: 'Banana pack, oats cup, chicken meal...',
                    ),
                    const SizedBox(height: 14),
                    _input(
                      'Description',
                      _descCtrl,
                      Icons.notes_rounded,
                      maxLines: 3,
                      hint: 'Fresh, homemade, low sugar, high protein...',
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _input(
                            'Price (RM)',
                            _priceCtrl,
                            Icons.payments_rounded,
                            keyboard: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            hint: '6.50',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _input(
                            'Quantity',
                            _qtyCtrl,
                            Icons.inventory_2_rounded,
                            keyboard: TextInputType.number,
                            hint: '1',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _sectionLabel('Category'),
                    const SizedBox(height: 8),
                    RepaintBoundary(child: _categorySelector()),
                    const SizedBox(height: 14),
                    _input(
                      'COD pickup location',
                      _locationCtrl,
                      Icons.location_on_rounded,
                      hint: 'UTeM, hostel, Melaka...',
                    ),
                    const SizedBox(height: 14),
                    _input(
                      'Expiry / best before (optional)',
                      _expiryCtrl,
                      Icons.event_rounded,
                      hint: 'Today 8 PM, 18/6/2026...',
                    ),
                    const SizedBox(height: 18),
                    RepaintBoundary(child: _codNotice()),
                    const SizedBox(height: 22),
                    _submitButton(),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 20, 10),
      child: Row(
        children: [
          _circleButton(
            Icons.arrow_back_ios_new_rounded,
            () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isEditing ? 'Edit Listing' : 'Sell Food',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 28,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.isEditing
                      ? 'Update stock, photo, price and details'
                      : 'Post a safe COD listing to NutriMarket',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.72),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF33521F), Color(0xFF1A2415), Color(0xFF10150E)],
        ),
        border: Border.all(color: lime.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: lime,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              widget.isEditing
                  ? Icons.edit_rounded
                  : Icons.add_business_rounded,
              color: Colors.black,
              size: 31,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.isEditing ? 'Update product' : 'Create listing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 22,
                          height: 0.95,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    _miniBadge('COD'),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  'Add clear details so buyers can order and chat with confidence.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.82),
                    fontSize: 13,
                    height: 1.28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPicker() {
    Uint8List? bytes;
    if (_imageBase64.isNotEmpty) {
      try {
        bytes = base64Decode(_imageBase64);
      } catch (_) {}
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickImage,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        height: 190,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: card.withOpacity(0.94),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: lime.withOpacity(0.16)),
        ),
        child: bytes == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: lime.withOpacity(0.13),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.add_photo_alternate_rounded,
                      color: lime,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Add food photo',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'A clear image makes the listing feel trusted',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: soft.withOpacity(0.72),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                    cacheWidth: 720,
                    gaplessPlayback: true,
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.62),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.10),
                        ),
                      ),
                      child: Text(
                        'Change photo',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.outfit(
        color: soft,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _input(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    String hint = '',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel(label),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            color: card.withOpacity(0.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboard,
            maxLines: maxLines,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(icon, color: lime, size: 20),
              hintText: hint,
              hintStyle: GoogleFonts.outfit(
                color: soft.withOpacity(0.44),
                fontWeight: FontWeight.w600,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _categorySelector() {
    return SizedBox(
      height: 43,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          final item = _categories[index];
          final selected = _category == item.label;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_category == item.label) return;
              HapticFeedback.selectionClick();
              setState(() => _category = item.label);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? lime : card.withOpacity(0.94),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? lime : Colors.white.withOpacity(0.06),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.icon,
                    color: selected ? Colors.black : soft,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.label,
                    style: GoogleFonts.outfit(
                      color: selected ? Colors.black : soft,
                      fontSize: 12.3,
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

  Widget _codNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card.withOpacity(0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: lime.withOpacity(0.13)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: lime.withOpacity(0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: lime,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'COD only marketplace',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Buyers will pay during pickup. Confirm time through chat.',
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(0.70),
                    fontSize: 12.2,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _submitButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: ElevatedButton(
        onPressed: _saving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: lime,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: _saving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.isEditing
                        ? Icons.save_rounded
                        : Icons.publish_rounded,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isEditing
                        ? 'Save Product Changes'
                        : 'Post Food Listing',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: card.withOpacity(0.92),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _miniBadge(String textValue) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Text(
        textValue,
        style: GoogleFonts.outfit(
          color: lime,
          fontSize: 10.8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _MarketCategory {
  const _MarketCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}
