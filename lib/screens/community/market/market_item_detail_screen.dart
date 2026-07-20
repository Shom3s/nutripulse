import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/market_item.dart';
import '../../../services/market_service.dart';
import 'add_market_item_screen.dart';
import '../../chat/private_chat_screen.dart';

class MarketItemDetailScreen extends StatefulWidget {
  const MarketItemDetailScreen({super.key, required this.item});

  final MarketItem item;

  @override
  State<MarketItemDetailScreen> createState() => _MarketItemDetailScreenState();
}

class _MarketItemDetailScreenState extends State<MarketItemDetailScreen>
    with AutomaticKeepAliveClientMixin {
  static const Color bg = Color(0xFF0F140D);
  static const Color lime = Color(0xFFD6FF60);
  static const Color card = Color(0xFF1A1F17);
  static const Color card2 = Color(0xFF23291F);
  static const Color soft = Color(0xFFB7C2A8);

  final TextEditingController _noteCtrl = TextEditingController();
  int _quantity = 1;
  bool _ordering = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _isMine =>
      FirebaseAuth.instance.currentUser?.uid == widget.item.sellerId;

  Future<void> _order() async {
    if (_ordering || _isMine) return;
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    setState(() => _ordering = true);

    try {
      await MarketService.createOrder(
        item: widget.item,
        quantity: _quantity,
        note: _noteCtrl.text,
      );
      if (!mounted) return;
      await _successSheet();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Order failed: $e',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _ordering = false);
    }
  }

  void _chatSeller() {
    if (_isMine) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: PrivateChatScreen(
            friendUid: widget.item.sellerId,
            friendName: widget.item.sellerName,
            friendPhotoBase64: widget.item.sellerPhotoBase64,
          ),
        ),
      ),
    );
  }

  Future<void> _editListing() async {
    HapticFeedback.lightImpact();
    final updated = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: AddMarketItemScreen(editItem: widget.item),
        ),
      ),
    );

    // The listing data shown on this detail screen is a snapshot. After a
    // successful edit, return to NutriMarket so the Firestore stream refreshes
    // the latest name, stock, photo and price immediately.
    if (updated == true && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _successSheet() async {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        decoration: const BoxDecoration(
          color: Color(0xFF10150E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: lime.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: lime,
                  size: 44,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'COD Order Sent',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Seller received your order request. Use chat to confirm pickup time and location.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: soft,
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: lime,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final total = widget.item.price * _quantity;

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
          child: Stack(
            children: [
              CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                cacheExtent: 420,
                slivers: [
                  SliverToBoxAdapter(child: RepaintBoundary(child: _topBar())),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, _isMine ? 26 : 126),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate.fixed([
                        RepaintBoundary(
                          child: _MarketHeroImage(
                            base64: widget.item.imageBase64,
                            height: 250,
                          ),
                        ),
                        const SizedBox(height: 18),
                        RepaintBoundary(child: _titleBlock()),
                        const SizedBox(height: 14),
                        RepaintBoundary(child: _quickPills()),
                        const SizedBox(height: 18),
                        RepaintBoundary(child: _descriptionCard()),
                        const SizedBox(height: 16),
                        RepaintBoundary(child: _sellerCard()),
                        const SizedBox(height: 16),
                        if (!_isMine) ...[
                          RepaintBoundary(child: _quantityCard(total)),
                          const SizedBox(height: 16),
                          _noteBox(),
                        ] else
                          RepaintBoundary(child: _ownListingNotice()),
                      ]),
                    ),
                  ),
                ],
              ),
              if (!_isMine)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: RepaintBoundary(child: _bottomBar(total)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 20, 8),
      child: Row(
        children: [
          _circleButton(
            Icons.arrow_back_ios_new_rounded,
            () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Food Details',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (_isMine)
            _circleButton(Icons.edit_rounded, _editListing)
          else
            _circleButton(Icons.chat_bubble_rounded, _chatSeller),
        ],
      ),
    );
  }

  Widget _titleBlock() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item.name,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 30,
                  height: 0.96,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.9,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'by ${widget.item.sellerName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: soft.withOpacity(0.70),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: lime.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: lime.withOpacity(0.16)),
          ),
          child: Text(
            'RM ${widget.item.price.toStringAsFixed(2)}',
            style: GoogleFonts.outfit(
              color: lime,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickPills() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _pill(Icons.payments_rounded, 'COD only'),
        _pill(Icons.category_rounded, widget.item.category),
        _pill(Icons.inventory_2_rounded, '${widget.item.quantity} left'),
        _pill(Icons.health_and_safety_rounded, widget.item.healthTag),
      ],
    );
  }

  Widget _descriptionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.notes_rounded, 'Listing information'),
          const SizedBox(height: 10),
          Text(
            widget.item.description.trim().isEmpty
                ? 'No description added.'
                : widget.item.description,
            style: GoogleFonts.outfit(
              color: soft,
              fontSize: 13.2,
              height: 1.36,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          _detailRow(
            Icons.location_on_rounded,
            'COD location',
            widget.item.location,
          ),
          if (widget.item.expiryDate.trim().isNotEmpty)
            _detailRow(
              Icons.event_rounded,
              'Best before',
              widget.item.expiryDate,
            ),
        ],
      ),
    );
  }

  Widget _sellerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: lime.withOpacity(0.14),
            child: Text(
              widget.item.sellerName.isEmpty
                  ? 'S'
                  : widget.item.sellerName[0].toUpperCase(),
              style: GoogleFonts.outfit(
                color: lime,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.sellerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Community seller • COD pickup',
                  style: GoogleFonts.outfit(
                    color: soft,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (!_isMine)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _chatSeller,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: lime,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Chat',
                  style: GoogleFonts.outfit(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _quantityCard(double total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cardHeader(Icons.shopping_bag_rounded, 'Order quantity'),
                const SizedBox(height: 6),
                Text(
                  'Total RM ${total.toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(
                    color: lime,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          _step(
            Icons.remove_rounded,
            _quantity > 1 ? () => setState(() => _quantity--) : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              '$_quantity',
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _step(
            Icons.add_rounded,
            _quantity < widget.item.quantity
                ? () => setState(() => _quantity++)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _noteBox() {
    return Container(
      decoration: _box(),
      child: TextField(
        controller: _noteCtrl,
        maxLines: 3,
        style: GoogleFonts.outfit(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
          hintText: 'Add pickup note for seller (optional)',
          hintStyle: GoogleFonts.outfit(
            color: soft.withOpacity(0.52),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _ownListingNotice() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _box(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: lime.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: lime,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'This is your listing. You can update stock, photo, name, price, pickup location and best-before details anytime.',
                  style: GoogleFonts.outfit(
                    color: soft,
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _editListing,
              style: ElevatedButton.styleFrom(
                backgroundColor: lime,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: Text(
                'Edit Product Listing',
                style: GoogleFonts.outfit(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _sellerMiniAction(
                  icon: widget.item.status == 'paused'
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                  label: widget.item.status == 'paused' ? 'Resume' : 'Pause',
                  onTap: () async {
                    try {
                      await MarketService.toggleItemStatus(widget.item);
                      if (mounted) Navigator.pop(context);
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not update status: $e')),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _sellerMiniAction(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete',
                  danger: true,
                  onTap: _confirmDeleteListing,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sellerMiniAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: danger
              ? Colors.redAccent.withOpacity(0.12)
              : Colors.white.withOpacity(0.055),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: danger
                ? Colors.redAccent.withOpacity(0.28)
                : Colors.white.withOpacity(0.06),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: danger ? Colors.redAccent : lime, size: 17),
            const SizedBox(width: 7),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: danger ? Colors.redAccent : Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteListing() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151B12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Delete listing?',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          'This will remove the product from NutriMarket. Existing orders will remain in Seller Orders.',
          style: GoogleFonts.outfit(color: soft, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(
                color: soft,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: GoogleFonts.outfit(
                color: Colors.redAccent,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      await MarketService.deleteItem(widget.item);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not delete listing: $e')));
    }
  }

  Widget _bottomBar(double total) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        MediaQuery.of(context).padding.bottom + 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0D120B).withOpacity(0.96),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.07))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total',
                  style: GoogleFonts.outfit(
                    color: soft,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'RM ${total.toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(
                    color: lime,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _ordering ? null : _order,
                style: ElevatedButton.styleFrom(
                  backgroundColor: lime,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _ordering
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        'Order COD',
                        style: GoogleFonts.outfit(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardHeader(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, color: lime, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 16.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: lime, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.outfit(
                  color: soft,
                  fontSize: 12.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: GoogleFonts.outfit(
                      color: Colors.white.withOpacity(0.84),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: lime, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white.withOpacity(0.84),
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.35 : 1,
        duration: const Duration(milliseconds: 160),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: lime.withOpacity(0.14),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: lime.withOpacity(0.10)),
          ),
          child: Icon(icon, color: lime, size: 20),
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

  BoxDecoration _box() {
    return BoxDecoration(
      color: card.withOpacity(0.94),
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    );
  }
}

class _MarketHeroImage extends StatefulWidget {
  const _MarketHeroImage({required this.base64, required this.height});

  final String base64;
  final double height;

  @override
  State<_MarketHeroImage> createState() => _MarketHeroImageState();
}

class _MarketHeroImageState extends State<_MarketHeroImage> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _decode(widget.base64);
  }

  @override
  void didUpdateWidget(covariant _MarketHeroImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.base64 != widget.base64) {
      _bytes = _decode(widget.base64);
    }
  }

  Uint8List? _decode(String value) {
    if (value.isEmpty) return null;
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _MarketItemDetailScreenState.card2,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: _bytes == null
          ? const Icon(
              Icons.restaurant_rounded,
              color: _MarketItemDetailScreenState.lime,
              size: 64,
            )
          : Image.memory(
              _bytes!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.low,
              cacheWidth: 780,
              gaplessPlayback: true,
            ),
    );
  }
}
