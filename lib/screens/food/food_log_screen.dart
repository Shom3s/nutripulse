import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../../services/food_ml_service.dart';
import '../../services/nutrition_service.dart';
import '../../services/meal_firestore_service.dart';
import '../../services/barcode_food_service.dart';
import '../../services/portion_estimator_service.dart';
import '../../services/gamification_service.dart';
import '../../models/meal_entry.dart';
import '../../theme/nutripulse_theme_controller.dart';
import 'barcode_scanner_screen.dart';

class FoodLogScreen extends StatefulWidget {
  const FoodLogScreen({super.key});

  @override
  State<FoodLogScreen> createState() => _FoodLogScreenState();
}

class _FoodLogScreenState extends State<FoodLogScreen>
    with TickerProviderStateMixin {
  // ── Design system (follows Settings theme mode) ───────────────
  NutriPalette get _palette => nutriThemeController.palette;
  Color get _bg => _palette.bg;
  Color get _lime => _palette.lime;
  Color get _surface => _palette.card;
  Color get _surface2 => _palette.card2;
  Color get _soft => _palette.subText;
  Color get _hair => _palette.border;

  // Dashboard background gradient (top -> middle -> bottom).
  List<Color> get _bgGradient => [
    _palette.topGradient,
    _palette.bg,
    _palette.bottomGradient,
  ];

  // Macro accent colors (reused across charts + cards)
  static const Color _cProtein = Color(0xFF7CA8FF);
  static const Color _cCarbs = Color(0xFFFFD24D);
  static const Color _cFat = Color(0xFFFF8B7A);
  static const Color _cSugar = Color(0xFFFF8BC8);

  bool _isScanning = false;
  bool _isSaving = false;
  File? _imageFile;
  Map<String, dynamic>? _mlResult;
  Map<String, dynamic>? _nutrition;
  double _portionG = 100.0;
  String _portionSize = 'Small';
  bool _portionEstimated = false;
  double _portionConfidence = 0.0;
  _PortionInputMode _portionInputMode = _PortionInputMode.unit;
  final _gramController = TextEditingController(text: '100');
  String _mealType = 'lunch';
  _EntryMethod _entryMethod = _EntryMethod.scan;
  String? _barcode;
  String? _barcodeBrand;
  String? _barcodeImageUrl;
  int _scanSession = 0;
  DateTime? _analyzeStartedAt;

  final List<String> _mealTypes = ['breakfast', 'lunch', 'dinner', 'snack'];
  final _searchController = TextEditingController();
  Timer? _manualSearchDebounce;

  @override
  void dispose() {
    _manualSearchDebounce?.cancel();
    _searchController.dispose();
    _gramController.dispose();
    super.dispose();
  }

  int _beginAnalyzeSession({File? image, bool clearBarcode = true}) {
    final session = ++_scanSession;

    setState(() {
      _isScanning = true;
      _isSaving = false;

      // Important: clear old result first.
      // Without this, the body keeps showing the previous result card,
      // so the analyzing screen may not appear on the 2nd scan.
      _mlResult = null;
      _nutrition = null;

      _imageFile = image;

      if (clearBarcode) {
        _barcode = null;
        _barcodeBrand = null;
        _barcodeImageUrl = null;
      }
    });

    return session;
  }

  bool _isActiveScan(int session) {
    return mounted && _scanSession == session;
  }

  Future<void> _allowAnalyzeFrame() async {
    // Gives Flutter one frame to show the analyzing UI before ML/network work.
    await Future<void>.delayed(const Duration(milliseconds: 90));
  }

  int _startAnalyzing({File? image, bool clearBarcode = true}) {
    final session = ++_scanSession;
    _analyzeStartedAt = DateTime.now();

    setState(() {
      _isScanning = true;
      _isSaving = false;

      // Clear old result so the analyzing page appears every scan.
      _mlResult = null;
      _nutrition = null;

      if (image != null) {
        _imageFile = image;
      }

      if (clearBarcode) {
        _barcode = null;
        _barcodeBrand = null;
        _barcodeImageUrl = null;
      }
    });

    return session;
  }

  bool _isActiveAnalyzeSession(int session) {
    return mounted && _scanSession == session;
  }

  Future<void> _showAnalyzingFrame() async {
    // Lets Flutter paint the analyzing screen before ML/API work starts.
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  Future<void> _finishAnalyzingSmoothly(int session) async {
    if (!_isActiveAnalyzeSession(session)) return;

    final started = _analyzeStartedAt;
    if (started != null) {
      final elapsed = DateTime.now().difference(started);
      const minimumVisible = Duration(milliseconds: 1500);

      if (elapsed < minimumVisible) {
        await Future<void>.delayed(minimumVisible - elapsed);
      }
    }

    if (_isActiveAnalyzeSession(session)) {
      setState(() => _isScanning = false);
    }
  }

  // ── Barcode scanner ─────────────────────────────────────────
  Future<void> _scanBarcode() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );

    if (scannedCode == null || scannedCode.trim().isEmpty) return;

    final session = _beginAnalyzeSession(image: null, clearBarcode: false);

    _barcode = scannedCode.trim();
    _barcodeBrand = null;
    _barcodeImageUrl = null;

    await _allowAnalyzeFrame();

    try {
      final product = await BarcodeFoodService.getFoodByBarcode(
        scannedCode,
      ).timeout(const Duration(seconds: 12));

      if (!_isActiveScan(session)) return;

      if (product == null) {
        setState(() => _isScanning = false);
        _showError(
          'Barcode not found. Try another product or search manually.',
        );
        return;
      }

      setState(() {
        _mlResult = {
          'foodName': product['name'],
          'confidence': 1.0,
          'top3': [],
          'barcode': scannedCode,
        };
        _nutrition = product;
        _barcodeBrand = (product['brand'] ?? '').toString();
        _barcodeImageUrl = (product['imageUrl'] ?? '').toString();
        _portionSize = 'Medium';
        _portionEstimated = false;
        _portionConfidence = 1.0; // packaged food: serving comes from the label
        _portionG = ((product['serving_grams'] as num?)?.toDouble() ?? 100.0);
      });
      await _finishAnalyzingSmoothly(session);
    } catch (e) {
      if (!_isActiveScan(session)) return;
      setState(() => _isScanning = false);
      _showError('Could not read barcode nutrition: $e');
    }
  }

  // ── Camera / Gallery ─────────────────────────────────────────
  Future<void> _scanFromCamera() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 72,
    );
    if (picked == null) return;
    await _processImage(File(picked.path));
  }

  Future<void> _scanFromGallery() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 72,
    );
    if (picked == null) return;
    await _processImage(File(picked.path));
  }

  // ── Process image ─────────────────────────────────────────────
  Future<void> _processImage(File image) async {
    final session = _startAnalyzing(image: image);
    await _showAnalyzingFrame();

    try {
      final ml = await FoodMLService.classifyFood(
        image,
      ).timeout(const Duration(seconds: 12));

      if (!_isActiveAnalyzeSession(session)) return;

      final confidence = (ml['confidence'] as num?)?.toDouble() ?? 0.0;
      final foodName = (ml['foodName'] ?? 'unknown').toString();

      debugPrint(
        'ML result: $foodName at ${(confidence * 100).toStringAsFixed(1)}%',
      );

      if (foodName == 'unknown' || confidence == 0.0) {
        await _finishAnalyzingSmoothly(session);
        if (_isActiveAnalyzeSession(session)) {
          _showFoodPickerDialog();
        }
        return;
      }

      final nutrition = await NutritionService.getNutrition(
        foodName,
      ).timeout(const Duration(seconds: 8));

      final portionEstimate =
          await PortionEstimatorService.estimatePortion(
            imageFile: image,
            foodName: foodName,
          ).timeout(
            const Duration(seconds: 4),
            onTimeout: () {
              return PortionEstimatorService.fallback(foodName);
            },
          );

      if (!_isActiveAnalyzeSession(session)) return;

      // Actually apply the AI portion estimate (it was being discarded before).
      final est = _readPortionEstimate(
        portionEstimate,
        foodName,
        nutrition: nutrition,
      );

      setState(() {
        _mlResult = ml;
        _nutrition = nutrition;
        _portionSize = est.size;
        _portionEstimated = est.estimated;
        _portionConfidence = est.confidence;
        _portionG = est.grams;
      });

      await _finishAnalyzingSmoothly(session);

      if (confidence < 0.4 && mounted && _isActiveAnalyzeSession(session)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Low confidence (${(confidence * 100).toInt()}%). '
              'You can edit manually if wrong.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Process image error: $e');
      await _finishAnalyzingSmoothly(session);
      if (_isActiveAnalyzeSession(session)) {
        _showFoodPickerDialog();
      }
    }
  }

  // ── Read a portion estimate result robustly ──────────────────
  // A normal phone photo cannot measure grams accurately because there is no
  // real-world scale/reference object. So this keeps the scan result close to
  // the normal serving from the CSV and only accepts image-estimated grams when
  // they are confident and inside a realistic range.
  _PortionEstimate _readPortionEstimate(
    dynamic raw,
    String foodName, {
    Map<String, dynamic>? nutrition,
  }) {
    double? rawGrams;
    String? size;
    double? confidence;
    bool estimated = true;

    if (raw is num) {
      rawGrams = raw.toDouble();
    } else if (raw is Map) {
      final gValue =
          raw['grams'] ??
          raw['portionG'] ??
          raw['portion_g'] ??
          raw['serving_grams'] ??
          raw['value'];
      if (gValue is num) rawGrams = gValue.toDouble();

      final s = (raw['size'] ?? raw['portionSize'] ?? raw['label'])?.toString();
      if (s != null && s.isNotEmpty) size = _normalizeSize(s);

      final cValue = raw['confidence'] ?? raw['conf'];
      if (cValue is num) confidence = cValue.toDouble();

      if (raw['estimated'] is bool) estimated = raw['estimated'] as bool;
    } else if (raw != null) {
      // Object with named fields — read via dynamic access, guarded.
      try {
        rawGrams = (raw.grams as num?)?.toDouble();
      } catch (_) {}
      try {
        size = _normalizeSize(raw.size as String);
      } catch (_) {}
      try {
        confidence = (raw.confidence as num?)?.toDouble();
      } catch (_) {}
    }

    final normalG = _normalServingGrams(foodName, nutrition);
    final minG = _reasonableMinForFood(foodName, normalG);
    final maxG = _reasonableMaxForFood(foodName, normalG);

    // If the service only gives grams, convert it to a simple size bucket.
    if (size == null || size.isEmpty) {
      if (rawGrams == null) {
        size = 'Medium';
      } else if (rawGrams <= normalG * 0.75) {
        size = 'Small';
      } else if (rawGrams >= normalG * 1.22) {
        size = 'Large';
      } else {
        size = 'Medium';
      }
    }

    final conf = (confidence ?? 0.45).clamp(0.0, 1.0).toDouble();

    // Main fix:
    // Do not trust 500g/600g image estimates unless confidence is high and
    // the grams are realistic for this specific food.
    final rawLooksValid =
        rawGrams != null &&
        rawGrams > 0 &&
        rawGrams >= minG &&
        rawGrams <= maxG &&
        conf >= 0.72;

    double g = rawLooksValid
        ? rawGrams!
        : _gramsFromSize(foodName, size, normalG);

    g = g.clamp(minG, maxG).toDouble();
    g = _snapToNearest(g, 5);

    return _PortionEstimate(
      grams: g,
      size: size,
      confidence: rawLooksValid ? conf : math.min(conf, 0.55),
      estimated: estimated,
    );
  }

  double _normalServingGrams(String foodName, Map<String, dynamic>? nutrition) {
    final fromDb = (nutrition?['serving_grams'] as num?)?.toDouble();
    if (fromDb != null && fromDb >= 20 && fromDb <= 900) {
      return fromDb;
    }

    final l = foodName.toLowerCase();

    if (l.contains('nasi lemak')) return 350;
    if (l.contains('fried_noodles') ||
        l.contains('fried noodles') ||
        l.contains('mee goreng'))
      return 320;
    if (l.contains('fried_rice') ||
        l.contains('fried rice') ||
        l.contains('nasi goreng'))
      return 330;
    if (l.contains('mixed_rice') ||
        l.contains('mixed rice') ||
        l.contains('nasi campur'))
      return 400;
    if (l.contains('laksa')) return 450;
    if (l.contains('fish_and_chips') || l.contains('fish and chips'))
      return 380;
    if (l.contains('hamburger') || l.contains('burger')) return 220;
    if (l.contains('kaya_toast') || l.contains('kaya toast')) return 110;
    if (l.contains('roti_canai') || l.contains('roti canai')) return 95;
    if (l.contains('satay')) return 180;
    if (l.contains('popiah')) return 120;

    return 250;
  }

  double _reasonableMinForFood(String foodName, double normalG) {
    final l = foodName.toLowerCase();

    if (l.contains('roti canai')) return 60;
    if (l.contains('kaya toast')) return 60;
    if (l.contains('satay')) return 80;
    if (l.contains('popiah')) return 70;
    if (l.contains('burger') || l.contains('hamburger')) return 120;

    return math.max(50, normalG * 0.55).toDouble();
  }

  double _reasonableMaxForFood(String foodName, double normalG) {
    final l = foodName.toLowerCase();

    // Allow users to add more than one plate / bowl / piece.
    // The AI still starts with a normal serving, but manual quantity can go higher.
    if (l.contains('satay')) return 30 * 24.0; // 24 sticks
    if (l.contains('popiah')) return 60 * 10.0; // 10 pieces
    if (l.contains('roti canai')) return 95 * 6.0; // 6 pieces
    if (l.contains('kaya toast')) return 55 * 8.0; // 8 slices
    if (l.contains('bread') ||
        l.contains('toast') ||
        l.contains('roti gandum') ||
        l.contains('gandum penuh') ||
        l.contains('wholemeal'))
      return 35 * 12.0; // 12 slices
    if (l.contains('egg')) return 50 * 8.0; // 8 eggs
    if (l.contains('burger') || l.contains('hamburger'))
      return normalG * 3.0; // 3 burgers
    if (l.contains('laksa') ||
        l.contains('soup') ||
        l.contains('sup') ||
        l.contains('bubur') ||
        l.contains('porridge'))
      return normalG * 3.0; // 3 bowls
    if (l.contains('drink') ||
        l.contains('juice') ||
        l.contains('milk') ||
        l.contains('kopi') ||
        l.contains('teh') ||
        l.contains('air ') ||
        l.contains('smoothie'))
      return 250 * 4.0; // 4 cups
    if (l.contains('kuih') ||
        l.contains('cake') ||
        l.contains('donut') ||
        l.contains('doughnut') ||
        l.contains('muffin') ||
        l.contains('karipap') ||
        l.contains('curry puff') ||
        l.contains('pau'))
      return 45 * 12.0; // 12 pieces
    if (l.contains('nasi') ||
        l.contains('rice') ||
        l.contains('mee') ||
        l.contains('noodle') ||
        l.contains('fish and chips') ||
        l.contains('fish_and_chips'))
      return normalG * 3.0; // 3 plates

    return normalG * 4.0; // 4 servings
  }

  double _gramsFromSize(String foodName, String? size, double normalG) {
    final normalized = _normalizeSize(size ?? 'Medium');
    final minG = _reasonableMinForFood(foodName, normalG);
    final maxG = _reasonableMaxForFood(foodName, normalG);

    double g;
    switch (normalized) {
      case 'Small':
        g = normalG * 0.70;
        break;
      case 'Large':
        g = normalG * 1.18;
        break;
      case 'Medium':
      default:
        g = normalG;
        break;
    }

    return _snapToNearest(g.clamp(minG, maxG).toDouble(), 5);
  }

  double _snapToNearest(double value, int step) {
    return ((value / step).round() * step).toDouble();
  }

  // Your CSV stores calories/macros for the listed serving, not always per 100g.
  // So scale nutrition by selected grams ÷ serving_grams.
  double _nutritionScaleRatio() {
    final servingG =
        ((_nutrition?['serving_grams'] as num?)?.toDouble() ?? 100.0);
    if (servingG <= 0) return _portionG / 100.0;
    return (_portionG / servingG).clamp(0.05, 5.0).toDouble();
  }

  _PortionUnitData _portionUnitForFood(
    String foodName,
    Map<String, dynamic>? nutrition,
  ) {
    final lower = foodName.toLowerCase();
    final normalG = _normalServingGrams(foodName, nutrition);

    if (lower.contains('satay')) {
      return const _PortionUnitData(
        singular: 'stick',
        plural: 'sticks',
        gramsPerUnit: 30,
        step: 1,
        minUnits: 1,
        maxUnits: 24,
      );
    }

    if (lower.contains('popiah')) {
      return const _PortionUnitData(
        singular: 'piece',
        plural: 'pieces',
        gramsPerUnit: 60,
        step: 1,
        minUnits: 1,
        maxUnits: 10,
      );
    }

    if (lower.contains('roti canai')) {
      return const _PortionUnitData(
        singular: 'piece',
        plural: 'pieces',
        gramsPerUnit: 95,
        step: 0.5,
        minUnits: 0.5,
        maxUnits: 6,
      );
    }

    if (lower.contains('kaya toast')) {
      return const _PortionUnitData(
        singular: 'slice',
        plural: 'slices',
        gramsPerUnit: 55,
        step: 0.5,
        minUnits: 1,
        maxUnits: 8,
      );
    }

    if (lower.contains('bread') ||
        lower.contains('toast') ||
        lower.contains('roti gandum') ||
        lower.contains('gandum penuh') ||
        lower.contains('wholemeal')) {
      return const _PortionUnitData(
        singular: 'slice',
        plural: 'slices',
        gramsPerUnit: 35,
        step: 0.5,
        minUnits: 1,
        maxUnits: 12,
      );
    }

    if (lower.contains('laksa') ||
        lower.contains('soup') ||
        lower.contains('sup') ||
        lower.contains('bubur') ||
        lower.contains('porridge')) {
      return _PortionUnitData(
        singular: 'bowl',
        plural: 'bowls',
        gramsPerUnit: normalG,
        step: 0.5,
        minUnits: 0.5,
        maxUnits: 3,
      );
    }

    if (lower.contains('drink') ||
        lower.contains('juice') ||
        lower.contains('milk') ||
        lower.contains('kopi') ||
        lower.contains('teh') ||
        lower.contains('air ') ||
        lower.contains('smoothie')) {
      return const _PortionUnitData(
        singular: 'cup',
        plural: 'cups',
        gramsPerUnit: 250,
        step: 0.5,
        minUnits: 0.5,
        maxUnits: 4,
      );
    }

    if (lower.contains('egg')) {
      return const _PortionUnitData(
        singular: 'egg',
        plural: 'eggs',
        gramsPerUnit: 50,
        step: 1,
        minUnits: 1,
        maxUnits: 8,
      );
    }

    if (lower.contains('burger') || lower.contains('hamburger')) {
      return _PortionUnitData(
        singular: 'burger',
        plural: 'burgers',
        gramsPerUnit: normalG,
        step: 0.5,
        minUnits: 0.5,
        maxUnits: 3,
      );
    }

    if (lower.contains('kuih') ||
        lower.contains('cake') ||
        lower.contains('donut') ||
        lower.contains('doughnut') ||
        lower.contains('muffin') ||
        lower.contains('karipap') ||
        lower.contains('curry puff') ||
        lower.contains('pau')) {
      return const _PortionUnitData(
        singular: 'piece',
        plural: 'pieces',
        gramsPerUnit: 45,
        step: 1,
        minUnits: 1,
        maxUnits: 12,
      );
    }

    if (lower.contains('nasi') ||
        lower.contains('rice') ||
        lower.contains('mee') ||
        lower.contains('noodle') ||
        lower.contains('fish and chips') ||
        lower.contains('fish_and_chips')) {
      return _PortionUnitData(
        singular: 'plate',
        plural: 'plates',
        gramsPerUnit: normalG,
        step: 0.5,
        minUnits: 0.5,
        maxUnits: 3,
      );
    }

    return _PortionUnitData(
      singular: 'serving',
      plural: 'servings',
      gramsPerUnit: normalG,
      step: 0.5,
      minUnits: 0.5,
      maxUnits: 4,
    );
  }

  double _snapQuantity(double value, double step) {
    if (step <= 0) return value;
    return ((value / step).round() * step).toDouble();
  }

  String _formatQuantity(double value) {
    final rounded = double.parse(value.toStringAsFixed(1));
    if ((rounded - rounded.round()).abs() < 0.05) {
      return rounded.round().toString();
    }
    if ((rounded - 0.5).abs() < 0.05) return '½';
    if ((rounded - 1.5).abs() < 0.05) return '1½';
    if ((rounded - 2.5).abs() < 0.05) return '2½';
    return rounded.toStringAsFixed(1);
  }

  String _titleCaseUnit(String unit) {
    if (unit.trim().isEmpty) return 'Portion';
    final clean = unit.trim();
    return clean[0].toUpperCase() + clean.substring(1);
  }

  String _portionUnitModeLabel(_PortionUnitData unit) {
    return _titleCaseUnit(unit.singular);
  }

  String _formatPortionAmount(
    double grams,
    String foodName,
    Map<String, dynamic>? nutrition,
  ) {
    final unit = _portionUnitForFood(foodName, nutrition);
    var quantity = grams / unit.gramsPerUnit;
    quantity = quantity.clamp(unit.minUnits, unit.maxUnits).toDouble();
    quantity = _snapQuantity(quantity, unit.step);

    final label = quantity <= 1.0 ? unit.singular : unit.plural;
    return '${_formatQuantity(quantity)} $label';
  }

  double _quantityForCurrentPortion(String foodName) {
    final unit = _portionUnitForFood(foodName, _nutrition);
    final raw = _portionG / unit.gramsPerUnit;
    final clamped = raw.clamp(unit.minUnits, unit.maxUnits).toDouble();
    return _snapQuantity(clamped, unit.step);
  }

  void _setPortionByQuantity(String foodName, double quantity) {
    final unit = _portionUnitForFood(foodName, _nutrition);
    final q = _snapQuantity(
      quantity.clamp(unit.minUnits, unit.maxUnits).toDouble(),
      unit.step,
    );
    final grams = q * unit.gramsPerUnit;
    _portionG = _snapToNearest(grams, 1);
    _portionEstimated = false;
    _portionConfidence = 0.50;
    _syncGramController();

    if (q <= 0.75) {
      _portionSize = 'Small';
    } else if (q >= 1.5) {
      _portionSize = 'Large';
    } else {
      _portionSize = 'Medium';
    }
  }

  void _setPortionByGrams(String foodName, double grams) {
    final unit = _portionUnitForFood(foodName, _nutrition);
    final minG = unit.minUnits * unit.gramsPerUnit;
    final maxG = unit.maxUnits * unit.gramsPerUnit;
    final g = _snapToNearest(grams.clamp(minG, maxG).toDouble(), 1);

    _portionG = g;
    _portionEstimated = false;
    _portionConfidence = 0.50;
    _syncGramController();

    final normalG = unit.gramsPerUnit <= 0 ? 100.0 : unit.gramsPerUnit;
    final ratio = g / normalG;
    if (ratio <= 0.75) {
      _portionSize = 'Small';
    } else if (ratio >= 1.5) {
      _portionSize = 'Large';
    } else {
      _portionSize = 'Medium';
    }
  }

  String _formatGrams(double grams) => '${grams.round()}g';

  void _syncGramController() {
    final text = _portionG.round().toString();
    if (_gramController.text == text) return;
    _gramController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Widget _quantityStepButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: onTap == null ? 0.38 : 1,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _surface2,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: _hair),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  String _normalizeSize(String s) {
    final l = s.toLowerCase();
    if (l.startsWith('s')) return 'Small';
    if (l.startsWith('l') || l.contains('big')) return 'Large';
    if (l.startsWith('m') || l.contains('med') || l.contains('regular')) {
      return 'Medium';
    }
    return 'Medium';
  }

  // ── Food picker dialog (shown when AI can't recognize) ────────
  void _showFoodPickerDialog() {
    final controller = TextEditingController();

    // Quick select Malaysian foods
    const quickFoods = [
      'Nasi Lemak',
      'Roti Canai',
      'Laksa',
      'Nasi Goreng',
      'Mee Goreng',
      'Satay',
      'Kaya Toast',
      'Popiah',
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.restaurant_rounded, color: _lime, size: 22),
              const SizedBox(width: 8),
              Text(
                'What food is this?',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Show scanned image preview if available
                if (_imageFile != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _imageFile!,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                Text(
                  'AI could not recognize this food.\nType the name or pick from the list:',
                  style: GoogleFonts.outfit(
                    color: _soft,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),

                // Text input
                TextField(
                  controller: controller,
                  autofocus: true,
                  style: GoogleFonts.outfit(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'e.g. nasi lemak...',
                    hintStyle: GoogleFonts.outfit(color: _soft),
                    filled: true,
                    fillColor: _surface2,
                    prefixIcon: Icon(Icons.search, color: _soft),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Quick select chips
                Text(
                  'Quick select:',
                  style: GoogleFonts.outfit(color: _soft, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: quickFoods
                      .map(
                        (food) => GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            _manualSearch(food);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _surface2,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _hair),
                            ),
                            child: Text(
                              food,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _imageFile = null);
              },
              child: Text('Cancel', style: GoogleFonts.outfit(color: _soft)),
            ),
            ElevatedButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) return;
                Navigator.pop(ctx);
                _manualSearch(text);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _lime,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Search',
                style: GoogleFonts.outfit(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Manual search ─────────────────────────────────────────────
  Future<void> _manualSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    final selectedFood = await _openFoodSearchSheet(initialQuery: cleanQuery);

    if (selectedFood == null) return;

    final session = _startAnalyzing();
    await _showAnalyzingFrame();

    if (!_isActiveAnalyzeSession(session)) return;

    final name = (selectedFood['name'] ?? cleanQuery).toString();

    // Manual search should not reuse an old scanned photo.
    // It gets its picture from the CSV/API image URL first, then from free
    // online sources (Wikipedia/Wikimedia/Openverse) when the CSV has no
    // usable image URL.
    final manualImageUrl = await _foodImageUrlForFood(selectedFood, name);

    if (!_isActiveAnalyzeSession(session)) return;

    setState(() {
      _mlResult = {
        'foodName': name,
        'confidence': 1.0,
        'top3': [],
        'source': selectedFood['source'] ?? 'offline_database',
      };
      _nutrition = selectedFood;
      _imageFile = null;
      _portionSize = 'Medium';
      _portionEstimated = false;
      _portionConfidence = 1.0; // manual entry: exact serving the user picked
      _portionG =
          ((selectedFood['serving_grams'] as num?)?.toDouble() ?? 100.0);
      _barcode = null;
      _barcodeBrand = '';
      _barcodeImageUrl = manualImageUrl;
    });

    await _finishAnalyzingSmoothly(session);
  }

  String _randomDefaultFoodQuery() {
    const options = [
      'nasi',
      'ayam',
      'roti',
      'mee',
      'rice',
      'egg',
      'chicken',
      'fish',
      'kuih',
      'fruit',
      'milk',
      'bread',
      'snack',
      'drink',
      'burger',
      'laksa',
      'satay',
    ];

    final index = DateTime.now().millisecondsSinceEpoch % options.length;
    return options[index];
  }

  Future<Map<String, dynamic>?> _openFoodSearchSheet({
    required String initialQuery,
  }) async {
    // Dashboard-style smooth popup:
    // 1) Open the bottom sheet first with a very light placeholder.
    // 2) Build the real search UI only after the popup animation settles.
    // 3) Load random/default foods after the UI is already visible.
    // This removes the opening jank caused by building the list + keyboard work
    // during the bottom-sheet route animation.
    final manualStartQuery = initialQuery.trim();
    final defaultQuery = manualStartQuery.isEmpty
        ? _randomDefaultFoodQuery()
        : manualStartQuery;
    final controller = TextEditingController(text: manualStartQuery);

    final sheetReady = ValueNotifier<bool>(false);
    final searchState = ValueNotifier<_FoodDatabaseSearchState>(
      const _FoodDatabaseSearchState(),
    );

    var sheetAlive = true;
    var bootStarted = false;
    var searchGeneration = 0;
    var lastSearchQuery = '';

    void hideKeyboard() {
      FocusManager.instance.primaryFocus?.unfocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    }

    Future<void> performSearch(
      String value, {
      bool hideKeyboardOnSubmit = false,
      bool isDefaultLoad = false,
    }) async {
      if (!sheetAlive) return;

      if (hideKeyboardOnSubmit) hideKeyboard();

      final typedQuery = value.trim();
      final query = typedQuery.isEmpty ? _randomDefaultFoodQuery() : typedQuery;

      if (query == lastSearchQuery &&
          searchState.value.results.isNotEmpty &&
          !searchState.value.loading) {
        return;
      }

      final requestId = ++searchGeneration;
      lastSearchQuery = query;
      searchState.value = searchState.value.copyWith(loading: true);

      // Let the sheet/keyboard finish its frame before CSV filtering runs.
      await Future<void>.delayed(
        isDefaultLoad
            ? const Duration(milliseconds: 80)
            : const Duration(milliseconds: 32),
      );

      final found = await NutritionService.searchFoods(query);

      if (!sheetAlive || requestId != searchGeneration) return;

      searchState.value = _FoodDatabaseSearchState(
        results: found,
        loading: false,
      );
    }

    final selectedFood = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      builder: (sheetContext) {
        if (!bootStarted) {
          bootStarted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            // Bottom-sheet entrance should be smooth first.
            await Future<void>.delayed(const Duration(milliseconds: 320));
            if (!sheetAlive) return;
            sheetReady.value = true;

            // Then wait one more short beat before loading the default foods.
            await Future<void>.delayed(const Duration(milliseconds: 220));
            if (!sheetAlive) return;
            await performSearch(defaultQuery, isDefaultLoad: true);
          });
        }

        return DraggableScrollableSheet(
          initialChildSize: 0.90,
          minChildSize: 0.60,
          maxChildSize: 0.96,
          builder: (_, scrollController) {
            return RepaintBoundary(
              child: Container(
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(34),
                  ),
                  border: Border.all(color: _hair),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 6,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Expanded(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: sheetReady,
                        builder: (context, ready, _) {
                          if (!ready) {
                            return _foodDatabaseOpeningPlaceholder(
                              onClose: () => Navigator.pop(sheetContext),
                            );
                          }

                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  16,
                                  20,
                                  12,
                                ),
                                child:
                                    ValueListenableBuilder<
                                      _FoodDatabaseSearchState
                                    >(
                                      valueListenable: searchState,
                                      builder: (context, state, _) {
                                        return _foodDatabaseHeader(
                                          resultCount: state.results.length,
                                          loading: state.loading,
                                          onClose: () =>
                                              Navigator.pop(sheetContext),
                                        );
                                      },
                                    ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  0,
                                  20,
                                  12,
                                ),
                                child:
                                    ValueListenableBuilder<
                                      _FoodDatabaseSearchState
                                    >(
                                      valueListenable: searchState,
                                      builder: (context, state, _) {
                                        return _premiumFoodSearchBar(
                                          controller: controller,
                                          loading: state.loading,
                                          onSubmit: (value) => performSearch(
                                            value,
                                            hideKeyboardOnSubmit: true,
                                          ),
                                          onChanged: (value) {
                                            _manualSearchDebounce?.cancel();
                                            _manualSearchDebounce = Timer(
                                              const Duration(milliseconds: 850),
                                              () => performSearch(value),
                                            );
                                          },
                                        );
                                      },
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child:
                                    ValueListenableBuilder<
                                      _FoodDatabaseSearchState
                                    >(
                                      valueListenable: searchState,
                                      builder: (context, state, _) {
                                        final visibleResults = state.results;
                                        final query = controller.text.trim();

                                        if (visibleResults.isEmpty &&
                                            !state.loading) {
                                          return _emptyFoodSearchState(query);
                                        }

                                        return ListView.builder(
                                          key: const PageStorageKey<String>(
                                            'food-database-results',
                                          ),
                                          controller: scrollController,
                                          physics:
                                              const ClampingScrollPhysics(),
                                          keyboardDismissBehavior:
                                              ScrollViewKeyboardDismissBehavior
                                                  .onDrag,
                                          primary: false,
                                          clipBehavior: Clip.hardEdge,
                                          cacheExtent: 60,
                                          addAutomaticKeepAlives: false,
                                          addRepaintBoundaries: true,
                                          addSemanticIndexes: false,
                                          padding: const EdgeInsets.fromLTRB(
                                            20,
                                            2,
                                            20,
                                            28,
                                          ),
                                          itemCount: visibleResults.length + 1,
                                          itemBuilder: (_, index) {
                                            if (index ==
                                                visibleResults.length) {
                                              final customQuery = query.isEmpty
                                                  ? lastSearchQuery
                                                  : query;
                                              return RepaintBoundary(
                                                child: _customEstimateTile(
                                                  query: customQuery.isEmpty
                                                      ? defaultQuery
                                                      : customQuery,
                                                  onTap: () {
                                                    hideKeyboard();
                                                    Navigator.pop(
                                                      sheetContext,
                                                      NutritionService.manualEstimate(
                                                        customQuery.isEmpty
                                                            ? defaultQuery
                                                            : customQuery,
                                                      ),
                                                    );
                                                  },
                                                ),
                                              );
                                            }

                                            final food = visibleResults[index];
                                            return RepaintBoundary(
                                              child: _foodSearchResultTile(
                                                food,
                                                onTap: () {
                                                  hideKeyboard();
                                                  Navigator.pop(
                                                    sheetContext,
                                                    food,
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    sheetAlive = false;
    _manualSearchDebounce?.cancel();
    controller.dispose();
    sheetReady.dispose();
    searchState.dispose();
    return selectedFood;
  }

  Widget _foodDatabaseOpeningPlaceholder({required VoidCallback onClose}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _lime.withOpacity(0.13),
                  _surface.withOpacity(0.96),
                  _surface2.withOpacity(0.90),
                ],
              ),
              border: Border.all(color: _lime.withOpacity(0.18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: _lime.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(19),
                    border: Border.all(color: _lime.withOpacity(0.26)),
                  ),
                  child: Icon(
                    Icons.manage_search_rounded,
                    color: _lime,
                    size: 31,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Food Database',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.65,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.20),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.10)),
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _lime.withOpacity(0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _lime.withOpacity(0.18)),
            ),
            child: Text(
              'Opening database...',
              style: GoogleFonts.outfit(
                color: _lime,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _foodDatabaseHeader({
    required int resultCount,
    required bool loading,
    required VoidCallback onClose,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _lime.withOpacity(0.16),
            _surface.withOpacity(0.98),
            _surface2.withOpacity(0.92),
          ],
        ),
        border: Border.all(color: _lime.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: _lime.withOpacity(0.16),
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: _lime.withOpacity(0.32)),
            ),
            child: Icon(Icons.manage_search_rounded, color: _lime, size: 31),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Food Database',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.65,
                  ),
                ),
                if (loading) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Searching...',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: _soft,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.20),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.10)),
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _databasePill(IconData icon, String label) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _lime, size: 13),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: Colors.white.withOpacity(0.88),
                  fontSize: 10.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _premiumFoodSearchBar({
    required TextEditingController controller,
    required bool loading,
    required ValueChanged<String> onSubmit,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _hair),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _lime.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.search_rounded, color: _lime, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: false,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
              ),
              decoration: InputDecoration(
                hintText: 'Search nasi ayam, roti canai, egg...',
                hintStyle: GoogleFonts.outfit(
                  color: _soft.withOpacity(0.72),
                  fontWeight: FontWeight.w600,
                  fontSize: 13.2,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: onChanged,
              onSubmitted: onSubmit,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => onSubmit(controller.text),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: 48,
              height: 48,
              margin: const EdgeInsets.only(right: 7),
              decoration: BoxDecoration(
                color: _lime,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _lime.withOpacity(0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.black,
                      size: 25,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _foodFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final icon = switch (label) {
      'High Protein' => Icons.fitness_center_rounded,
      'Low Calorie' => Icons.local_fire_department_rounded,
      'Malaysian' => Icons.rice_bowl_rounded,
      'Drinks' => Icons.local_drink_rounded,
      'Snacks' => Icons.cookie_rounded,
      _ => Icons.grid_view_rounded,
    };

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _lime : _surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? _lime : _hair),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? Colors.black : _soft, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: selected ? Colors.black : Colors.white,
                fontSize: 12.4,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniInfoChip(String text) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _hair),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(
            color: _soft,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _emptyFoodSearchState(String query) {
    final hasQuery = query.trim().isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _lime.withOpacity(0.28),
                    _lime.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Icon(
                hasQuery
                    ? Icons.search_off_rounded
                    : Icons.restaurant_menu_rounded,
                color: _lime,
                size: 39,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasQuery ? 'No exact match yet' : 'Search your food',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 23,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? 'Use the custom estimate below or try a simpler food name like "nasi ayam" or "egg".'
                  : 'Search Malaysian meals, snacks, drinks, packaged foods and common international foods.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: _soft,
                fontSize: 13.2,
                height: 1.36,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filteredFoodSearchState(String filter) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, color: _lime, size: 42),
            const SizedBox(height: 14),
            Text(
              'No $filter results',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try All, or search with another food name.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: _soft,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _foodSearchResultTile(
    Map<String, dynamic> food, {
    required VoidCallback onTap,
  }) {
    final name = (food['name'] ?? 'Unknown food').toString();
    final category = (food['category'] ?? '').toString();
    final cuisine = (food['cuisine'] ?? '').toString();
    final serving = (food['serving'] ?? food['servingSize'] ?? '1 serving')
        .toString();
    final calories = ((food['calories'] as num?)?.toDouble() ?? 0).round();
    final protein = ((food['protein'] as num?)?.toDouble() ?? 0);
    final carbs = ((food['carbs'] as num?)?.toDouble() ?? 0);
    final fat = ((food['fat'] as num?)?.toDouble() ?? 0);
    final sugar = ((food['sugar'] as num?)?.toDouble() ?? 0);
    final score = _calculateFoodScore(
      calories: calories.toDouble(),
      protein: protein,
      sugar: sugar,
      fat: fat,
    );

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 13),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: _lime.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: _lime.withOpacity(0.14)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _foodSearchThumbnail(food, name),
                      ),
                      Positioned(
                        right: 5,
                        bottom: 5,
                        child: _foodScoreBadge(score),
                      ),
                    ],
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 16.6,
                                  height: 1.06,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.25,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: _lime,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Text(
                                'Add',
                                style: GoogleFonts.outfit(
                                  color: Colors.black,
                                  fontSize: 12.4,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 7,
                          runSpacing: 6,
                          children: [
                            _foodMetaPill(
                              Icons.local_fire_department_rounded,
                              '$calories kcal',
                            ),
                            _foodMetaPill(Icons.restaurant_rounded, serving),
                            if (category.isNotEmpty)
                              _foodMetaPill(Icons.category_rounded, category),
                            if (cuisine.isNotEmpty)
                              _foodMetaPill(Icons.public_rounded, cuisine),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  _macroMiniBar('Protein', protein, 35, _cProtein),
                  const SizedBox(width: 8),
                  _macroMiniBar('Carbs', carbs, 90, _cCarbs),
                  const SizedBox(width: 8),
                  _macroMiniBar('Fat', fat, 35, _cFat),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _foodScoreBadge(int score) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _lime.withOpacity(0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_rounded, color: _lime, size: 10),
          const SizedBox(width: 3),
          Text(
            '$score',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _foodMetaPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.055)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _lime, size: 12),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 118),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white.withOpacity(0.82),
                fontSize: 10.8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _macroMiniBar(String label, double value, double goal, Color color) {
    final progress = goal <= 0
        ? 0.0
        : (value / goal).clamp(0.0, 1.0).toDouble();

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.045),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: _soft,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${value.toStringAsFixed(1)}g',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                height: 4,
                color: Colors.white.withOpacity(0.08),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(color: color),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customEstimateTile({
    required String query,
    required VoidCallback onTap,
  }) {
    final name = query.trim().isEmpty ? 'Custom Food' : query.trim();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_lime.withOpacity(0.16), _surface.withOpacity(0.98)],
          ),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _lime.withOpacity(0.24)),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _lime,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.black,
                size: 25,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Use smart estimate',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Create nutrition estimate for "$name"',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: _soft,
                      fontSize: 12.5,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: _lime, size: 28),
          ],
        ),
      ),
    );
  }

  _FoodAdviceResult _analyzeFoodAdvice({
    required String foodName,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required double sugar,
  }) {
    final lower = foodName.toLowerCase();
    int risk = 0;
    final reasons = <String>[];
    final advice = <String>[];

    if (calories >= 850) {
      risk += 3;
      reasons.add('Very high calories for one meal: ${calories.round()} kcal.');
      advice.add('Choose a smaller portion or split it into two meals.');
    } else if (calories >= 650) {
      risk += 2;
      reasons.add(
        'Calories are quite high for one meal: ${calories.round()} kcal.',
      );
      advice.add('Balance the rest of the day with lighter meals.');
    }

    if (fat >= 30) {
      risk += 3;
      reasons.add('Fat is high at ${fat.toStringAsFixed(1)}g.');
      advice.add('Reduce fried sides, creamy sauces, or oily toppings.');
    } else if (fat >= 22) {
      risk += 1;
      reasons.add('Fat is moderate-high at ${fat.toStringAsFixed(1)}g.');
    }

    if (sugar >= 22) {
      risk += 3;
      reasons.add('Sugar is high at ${sugar.toStringAsFixed(1)}g.');
      advice.add('Choose water or a lower-sugar drink.');
    } else if (sugar >= 14) {
      risk += 1;
      reasons.add('Sugar is moderate at ${sugar.toStringAsFixed(1)}g.');
    }

    if (protein < 10 && calories >= 350) {
      risk += 2;
      reasons.add('Protein is low for this calorie amount.');
      advice.add('Add egg, chicken, fish, tofu, tempeh, or lean protein.');
    } else if (protein >= 12) {
      advice.add('Protein is decent at ${protein.toStringAsFixed(1)}g.');
    }

    final isUsuallyHeavy =
        lower.contains('fried') ||
        lower.contains('burger') ||
        lower.contains('canai') ||
        lower.contains('nasi lemak');
    if (isUsuallyHeavy && calories >= 550) {
      risk += 1;
      reasons.add('This food can be oily or heavy depending on preparation.');
      advice.add('Keep the portion moderate and pair it with water.');
    }

    final healthierChoice =
        risk <= 1 &&
        calories <= 600 &&
        sugar < 14 &&
        fat < 22 &&
        (protein >= 8 || calories < 320);

    if (healthierChoice) {
      return _FoodAdviceResult(
        level: _FoodAdviceLevel.healthy,
        title: 'Healthier Choice',
        summary: '$foodName is a healthier choice for this portion.',
        reasons: [
          if (calories <= 600) 'Calories are reasonable for this portion.',
          if (sugar < 14) 'Sugar is not high.',
          if (fat < 22) 'Fat is within a reasonable range.',
          if (protein >= 8)
            'Protein is acceptable at ${protein.toStringAsFixed(1)}g.',
        ],
        advice: const [
          'Good option. Keep your portion balanced and stay hydrated.',
        ],
      );
    }

    if (advice.isEmpty) {
      advice.add(
        'Keep the portion balanced and add vegetables or fruit if possible.',
      );
    }

    if (risk >= 6) {
      return _FoodAdviceResult(
        level: _FoodAdviceLevel.warning,
        title: 'Smart Food Warning',
        summary: '$foodName may be heavy for your health goal at this portion.',
        reasons: reasons,
        advice: advice,
      );
    }

    return _FoodAdviceResult(
      level: _FoodAdviceLevel.caution,
      title: 'AI Nutrition Advice',
      summary:
          '$foodName is okay. Check the notes below to make it more balanced.',
      reasons: reasons,
      advice: advice,
    );
  }

  Future<bool> _showSmartFoodWarningSheet({
    required MealEntry entry,
    required _FoodAdviceResult advice,
  }) async {
    final proceed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        final accent = advice.level == _FoodAdviceLevel.warning
            ? const Color(0xFFFF8E6E)
            : const Color(0xFFFFD84D);
        final icon = advice.level == _FoodAdviceLevel.warning
            ? Icons.warning_amber_rounded
            : Icons.auto_awesome_rounded;

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F140D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(color: accent.withOpacity(0.28)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(icon, color: accent, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                advice.title,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                advice.summary,
                                style: GoogleFonts.outfit(
                                  color: Colors.white.withOpacity(0.78),
                                  fontSize: 13.5,
                                  height: 1.35,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  _bottomSheetMetricRow(entry),
                  const SizedBox(height: 18),
                  Text(
                    'Reason',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...advice.reasons
                      .take(4)
                      .map((item) => _adviceBullet(item, accent)),
                  const SizedBox(height: 14),
                  Text(
                    'AI Advice',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...advice.advice
                      .take(3)
                      .map((item) => _adviceBullet(item, _lime)),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.10),
                            ),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Text(
                            'Adjust Portion',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _lime,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            minimumSize: const Size.fromHeight(56),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Text(
                            'Add Anyway',
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.w900,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return proceed == true;
  }

  Widget _bottomSheetMetricRow(MealEntry entry) {
    return Row(
      children: [
        Expanded(
          child: _sheetMetric('Calories', '${entry.calories.round()}', 'kcal'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _sheetMetric('Protein', entry.protein.toStringAsFixed(1), 'g'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _sheetMetric('Sugar', entry.sugar.toStringAsFixed(1), 'g'),
        ),
      ],
    );
  }

  Widget _sheetMetric(String label, String value, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: _soft,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              text: value,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
              children: [
                TextSpan(
                  text: ' $unit',
                  style: GoogleFonts.outfit(
                    color: Colors.white.withOpacity(0.60),
                    fontSize: 11.5,
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

  Widget _adviceBullet(String text, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Icon(Icons.circle, size: 8, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.outfit(
                color: Colors.white.withOpacity(0.78),
                fontSize: 13.2,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Fast XP reward helper ─────────────────────────────────────
  Future<void> _awardMealXpFast(MealEntry entry) async {
    try {
      await GamificationService.onMealLogged(
        method: entry.method,
        calories: entry.calories,
        protein: entry.protein,
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      // XP should never make food logging feel slow or fail the saved meal.
      debugPrint('NutriPulse XP update skipped/late: $e');
    }
  }

  // ── Save to Firebase ──────────────────────────────────────────
  Future<void> _saveMeal() async {
    if (_nutrition == null || _isSaving) return;

    final ratio = _nutritionScaleRatio();
    final entryFoodName = (_nutrition!['name'] ?? 'Unknown Food').toString();
    final displayPortion = _formatPortionAmount(
      _portionG,
      entryFoodName,
      _nutrition,
    );

    final entry = MealEntry(
      id: '',
      name: entryFoodName,
      mealType: _mealType,
      calories: ((_nutrition!['calories'] as num?)?.toDouble() ?? 0.0) * ratio,
      protein: ((_nutrition!['protein'] as num?)?.toDouble() ?? 0.0) * ratio,
      carbs: ((_nutrition!['carbs'] as num?)?.toDouble() ?? 0.0) * ratio,
      fat: ((_nutrition!['fat'] as num?)?.toDouble() ?? 0.0) * ratio,
      portionG: _portionG,
      portionSize: displayPortion,
      portionEstimated: _portionEstimated,
      portionConfidence: _portionConfidence,
      method: _barcode != null
          ? 'barcode_scan'
          : (_imageFile != null ? 'ai_scan' : 'manual'),
      barcode: _barcode ?? '',
      brand: _barcodeBrand ?? '',
      sugar: ((_nutrition!['sugar'] as num?)?.toDouble() ?? 0.0) * ratio,
      imageUrl: _barcodeImageUrl ?? '',
      timestamp: DateTime.now(),
    );

    final foodAdvice = _analyzeFoodAdvice(
      foodName: entry.name,
      calories: entry.calories,
      protein: entry.protein,
      carbs: entry.carbs,
      fat: entry.fat,
      sugar: entry.sugar,
    );

    if (foodAdvice.level != _FoodAdviceLevel.healthy) {
      final proceed = await _showSmartFoodWarningSheet(
        entry: entry,
        advice: foodAdvice,
      );
      if (!proceed) return;
    }

    setState(() => _isSaving = true);

    try {
      await MealFirestoreService.saveMeal(
        entry,
      ).timeout(const Duration(seconds: 15));

      // Do not block the Add to Log flow while XP/level Firestore updates finish.
      // The meal is already saved, so return to the dashboard immediately and let
      // gamification update in the background.
      unawaited(_awardMealXpFast(entry));

      if (!mounted) return;
      setState(() => _isSaving = false);
      Navigator.pop(context, true);
    } on TimeoutException catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('Saving took too long. Check internet / Firestore rules.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError('Could not add meal: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _reset() => setState(() {
    _scanSession++;
    _isScanning = false;
    _imageFile = null;
    _mlResult = null;
    _nutrition = null;
    _portionG = 100.0;
    _portionSize = 'Small';
    _portionEstimated = false;
    _portionConfidence = 0.0;
    _portionInputMode = _PortionInputMode.unit;
    _gramController.text = '100';
    _searchController.clear();
    _barcode = null;
    _barcodeBrand = null;
    _barcodeImageUrl = null;
  });

  // ════════════════════════════════════════════════════════════════
  //  BUILD
  // ════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: nutriThemeController,
      builder: (context, _) {
        final palette = nutriThemeController.palette;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: palette.bg,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: Scaffold(
            backgroundColor: _bgGradient.first,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              elevation: 0,
              centerTitle: false,
              titleSpacing: 4,
              title: Text(
                'Log Food',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 19,
                ),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                if (_nutrition != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: TextButton.icon(
                      onPressed: () {
                        _reset();
                      },
                      icon: Icon(Icons.refresh_rounded, color: _lime, size: 18),
                      label: Text(
                        'Reset',
                        style: GoogleFonts.outfit(
                          color: _lime,
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            body: DecoratedBox(
              // Same gradient backdrop as the dashboard (top -> middle -> bottom).
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: _bgGradient,
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: _isScanning
                    ? _buildScanning()
                    : SingleChildScrollView(
                        key: ValueKey(_nutrition == null ? 'entry' : 'result'),
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: EdgeInsets.fromLTRB(
                          18,
                          MediaQuery.of(context).padding.top + 64,
                          18,
                          32,
                        ),
                        child: RepaintBoundary(
                          child: _nutrition == null
                              ? _buildEntryChoice()
                              : _buildResultCard(),
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  ENTRY CHOICE
  // ════════════════════════════════════════════════════════════════
  Widget _buildEntryChoice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Stagger(index: 0, child: _heroBanner()),
        const SizedBox(height: 18),
        _Stagger(index: 1, child: _methodSwitcher()),
        const SizedBox(height: 14),
        _Stagger(index: 2, child: _primaryActionPanel()),
        const SizedBox(height: 22),
        _Stagger(index: 3, child: _searchAndAddFoodCard()),
        const SizedBox(height: 26),
        _Stagger(index: 4, child: _quickAddHeader()),
        const SizedBox(height: 12),
        _Stagger(index: 5, child: _quickAddScroller()),
        const SizedBox(height: 24),
        _Stagger(index: 6, child: _smartWarningInfoCard()),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Animated hero banner ──────────────────────────────────────
  Widget _heroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _hair),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E1F22), Color(0xFF121214)],
        ),
      ),
      child: Row(
        children: [
          const _PulseAIOrb(size: 62),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Smart Food Log',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 21,
                    height: 1.05,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Scan, search and get instant AI nutrition advice.',
                  style: GoogleFonts.outfit(
                    color: _soft,
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 11),
                const _ShimmerBadge(label: 'AI Powered'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Segmented method switcher ─────────────────────────────────
  Widget _methodSwitcher() {
    final methods = <Map<String, dynamic>>[
      {
        'm': _EntryMethod.scan,
        'icon': Icons.camera_alt_rounded,
        'label': 'Scan',
      },
      {
        'm': _EntryMethod.barcode,
        'icon': Icons.qr_code_scanner_rounded,
        'label': 'Barcode',
      },
      {
        'm': _EntryMethod.manual,
        'icon': Icons.search_rounded,
        'label': 'Manual',
      },
    ];

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _hair),
      ),
      child: Row(
        children: methods.map((m) {
          final method = m['m'] as _EntryMethod;
          final selected = _entryMethod == method;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _entryMethod = method);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? _lime : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      m['icon'] as IconData,
                      size: 18,
                      color: selected ? Colors.black : _soft,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      m['label'] as String,
                      style: GoogleFonts.outfit(
                        color: selected ? Colors.black : _soft,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Primary action panel (changes with selected method) ───────
  Widget _primaryActionPanel() {
    Widget panel;
    switch (_entryMethod) {
      case _EntryMethod.scan:
        panel = _bigActionTile(
          key: const ValueKey('scan'),
          icon: Icons.camera_alt_rounded,
          title: 'Scan your meal',
          subtitle: 'Point your camera at the food — AI detects it instantly.',
          cta: 'Open Camera',
          onTap: _scanFromCamera,
          secondaryLabel: 'Upload from gallery',
          secondaryIcon: Icons.photo_library_rounded,
          onSecondary: _scanFromGallery,
        );
        break;
      case _EntryMethod.barcode:
        panel = _bigActionTile(
          key: const ValueKey('barcode'),
          icon: Icons.qr_code_scanner_rounded,
          title: 'Scan a barcode',
          subtitle: 'Get exact nutrition facts from packaged food barcodes.',
          cta: 'Scan Barcode',
          onTap: _scanBarcode,
        );
        break;
      case _EntryMethod.manual:
        panel = _bigActionTile(
          key: const ValueKey('manual'),
          icon: Icons.search_rounded,
          title: 'Search manually',
          subtitle: 'Find Malaysian meals, drinks, snacks and more.',
          cta: 'Open Food Database',
          onTap: _openManualSearchSheet,
        );
        break;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: panel,
    );
  }

  Widget _bigActionTile({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required String cta,
    required VoidCallback onTap,
    String? secondaryLabel,
    IconData? secondaryIcon,
    VoidCallback? onSecondary,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _lime.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _lime.withOpacity(0.28)),
                ),
                child: Icon(icon, color: _lime, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(
                        color: _soft,
                        fontSize: 12.5,
                        height: 1.3,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _GlowButton(
            label: cta,
            icon: Icons.arrow_forward_rounded,
            onTap: () {
              onTap();
            },
          ),
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () {
                onSecondary();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: _hair),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(secondaryIcon, color: _soft, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      secondaryLabel,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _searchAndAddFoodCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bolt_rounded, color: _lime, size: 19),
              const SizedBox(width: 7),
              Text(
                'Quick Search',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _hair),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.search_rounded, color: _soft, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search food or brand',
                      hintStyle: GoogleFonts.outfit(
                        color: _soft.withOpacity(0.7),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: _manualSearch,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    final query = _searchController.text.trim();
                    if (query.isEmpty) {
                      _openManualSearchSheet();
                    } else {
                      _manualSearch(query);
                    }
                  },
                  child: Container(
                    width: 46,
                    height: 46,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: _lime,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.black,
                      size: 23,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAddHeader() {
    return Row(
      children: [
        Text(
          'Quick Add',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _openManualSearchSheet,
          child: Text(
            'View all',
            style: GoogleFonts.outfit(
              color: _lime,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _quickAddScroller() {
    final foods = <Map<String, String>>[
      {
        'emoji': '🍛',
        'title': 'Nasi\nLemak',
        'calories': '≈ 560 kcal',
        'searchName': 'Nasi Lemak',
      },
      {
        'emoji': '🥞',
        'title': 'Roti\nCanai',
        'calories': '≈ 350 kcal',
        'searchName': 'Roti Canai',
      },
      {
        'emoji': '🍗',
        'title': 'Chicken\nBreast',
        'calories': '≈ 260 kcal',
        'searchName': 'Chicken Breast',
      },
      {
        'emoji': '🥣',
        'title': 'Oats',
        'calories': '≈ 190 kcal',
        'searchName': 'Oats',
      },
      {
        'emoji': '🥚',
        'title': 'Eggs',
        'calories': '≈ 155 kcal',
        'searchName': 'Egg',
      },
    ];

    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: foods.length,
        separatorBuilder: (_, __) => const SizedBox(width: 11),
        itemBuilder: (_, index) {
          final item = foods[index];
          return _quickAddCard(
            emoji: item['emoji']!,
            title: item['title']!,
            calories: item['calories']!,
            searchName: item['searchName']!,
          );
        },
      ),
    );
  }

  Widget _quickAddCard({
    required String emoji,
    required String title,
    required String calories,
    required String searchName,
  }) {
    return GestureDetector(
      onTap: () {
        _manualSearch(searchName);
      },
      child: Container(
        width: 108,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _hair),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(13),
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: const TextStyle(fontSize: 21)),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 12.5,
                height: 1.05,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              calories,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: _lime,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smartWarningInfoCard() {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Smart warning appears before saving meals high in calories, sugar or fat.',
              style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
            ),
            backgroundColor: _surface2,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _hair),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _lime.withOpacity(0.14),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                Icons.health_and_safety_rounded,
                color: _lime,
                size: 25,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Smart food warning',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'AI insights on sugar, fat and calories before you add a meal.',
                    style: GoogleFonts.outfit(
                      color: _soft,
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: _soft, size: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _openManualSearchSheet() async {
    final manualQuery = _searchController.text.trim();
    final selectedFood = await _openFoodSearchSheet(initialQuery: manualQuery);

    if (selectedFood == null) return;

    final session = _startAnalyzing();
    await _showAnalyzingFrame();

    if (!_isActiveAnalyzeSession(session)) return;

    final name = (selectedFood['name'] ?? 'Custom Food').toString();

    // Manual search image lookup is async, so we must await it before
    // assigning to the String? _barcodeImageUrl field.
    final manualImageUrl = await _foodImageUrlForFood(selectedFood, name);

    if (!_isActiveAnalyzeSession(session)) return;

    setState(() {
      _mlResult = {
        'foodName': name,
        'confidence': 1.0,
        'top3': [],
        'source': selectedFood['source'] ?? 'offline_database',
      };
      _nutrition = selectedFood;
      _imageFile = null;
      _portionSize = 'Medium';
      _portionEstimated = false;
      _portionConfidence = 1.0; // manual entry: exact serving the user picked
      _portionG =
          ((selectedFood['serving_grams'] as num?)?.toDouble() ?? 100.0);
      _barcode = null;
      _barcodeBrand = '';
      _barcodeImageUrl = manualImageUrl;
    });

    await _finishAnalyzingSmoothly(session);
  }

  // ════════════════════════════════════════════════════════════════
  //  ANALYZING SCREEN
  // ════════════════════════════════════════════════════════════════
  Widget _buildScanning() {
    return Center(
      key: ValueKey('analyzing-$_scanSession'),
      child: RepaintBoundary(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 460),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              final t = value.clamp(0.0, 1.0);
              return Transform.translate(
                offset: Offset(0, 22 * (1 - t)),
                child: Opacity(opacity: t, child: child),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: _hair),
              ),
              child: _PremiumAnalyzeTimeline(image: _imageFile),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════
  //  RESULT CARD
  // ════════════════════════════════════════════════════════════════
  Widget _buildResultCard() {
    final confidence = ((_mlResult?['confidence'] ?? 0) * 100).toInt();
    final ratio = _nutritionScaleRatio();

    final foodName = (_nutrition?['name'] ?? 'Unknown Food').toString();
    final calories =
        (((_nutrition!['calories'] as num?)?.toDouble() ?? 0.0) * ratio);
    final protein =
        (((_nutrition!['protein'] as num?)?.toDouble() ?? 0.0) * ratio);
    final carbs = (((_nutrition!['carbs'] as num?)?.toDouble() ?? 0.0) * ratio);
    final fat = (((_nutrition!['fat'] as num?)?.toDouble() ?? 0.0) * ratio);
    final sugar = (((_nutrition!['sugar'] as num?)?.toDouble() ?? 0.0) * ratio);

    final healthScore = _calculateFoodScore(
      calories: calories,
      protein: protein,
      sugar: sugar,
      fat: fat,
    );

    return Column(
      children: [
        _Stagger(index: 0, child: _resultHero(foodName, confidence)),
        const SizedBox(height: 14),
        _Stagger(index: 1, child: _mealTypeSelector()),
        const SizedBox(height: 16),
        // The headline: animated calorie ring + macro donut side by side.
        _Stagger(
          index: 2,
          child: _calorieAndMacroDashboard(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
          ),
        ),
        const SizedBox(height: 14),
        _Stagger(
          index: 3,
          child: _macroBarsCard(
            protein: protein,
            carbs: carbs,
            fat: fat,
            sugar: sugar,
          ),
        ),
        const SizedBox(height: 14),
        _Stagger(index: 4, child: _healthGaugeCard(healthScore)),
        const SizedBox(height: 14),
        _Stagger(
          index: 5,
          child: _smartNutritionInsightCard(
            foodName: foodName,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            sugar: sugar,
          ),
        ),
        const SizedBox(height: 14),
        if (_imageFile != null || _barcode != null) ...[
          _Stagger(index: 6, child: _portionEstimateCard()),
          const SizedBox(height: 14),
        ],
        _Stagger(index: 7, child: _advancedPortionSlider()),
        const SizedBox(height: 14),
        _Stagger(index: 8, child: _sourceInfoCard()),
        const SizedBox(height: 20),
        _Stagger(index: 9, child: _saveButton()),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Result hero (image + glass overlay) ───────────────────────
  Widget _resultHero(String foodName, int confidence) {
    return RepaintBoundary(
      child: Container(
        height: 230,
        width: double.infinity,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(28),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _heroImage(),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.45),
                      Colors.transparent,
                      Colors.black.withOpacity(0.72),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      foodName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 26,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.7,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _heroChip(
                          _barcode != null
                              ? 'Barcode'
                              : _imageFile != null
                              ? '$confidence% AI match'
                              : 'Manual entry',
                          Icons.auto_awesome_rounded,
                        ),
                        if ((_barcodeBrand ?? '').isNotEmpty)
                          _heroChip(_barcodeBrand!, Icons.storefront_rounded),
                        if (_barcode == null)
                          GestureDetector(
                            onTap: _showFoodPickerDialog,
                            child: _heroChip('Wrong food?', Icons.edit_rounded),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _firstAvailableImageUrl(Map<String, dynamic>? food) {
    if (food == null) return '';

    final candidates = [
      food['imageUrl'],
      food['image_url'],
      food['image'],
      food['photoUrl'],
      food['photo_url'],
      food['thumbnail'],
    ];

    for (final item in candidates) {
      final value = item?.toString().trim() ?? '';
      if (_isUsableImageUrl(value)) return value;
    }
    return '';
  }

  bool _isUsableImageUrl(String value) {
    final url = value.trim();
    if (!(url.startsWith('http://') || url.startsWith('https://'))) {
      return false;
    }

    final lower = url.toLowerCase();

    // source.unsplash.com is currently returning application errors for your
    // generated CSV links, so skip it and use free image lookup instead.
    if (lower.contains('source.unsplash.com')) return false;
    if (lower.contains('application-error')) return false;

    // Avoid common non-image pages.
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return false;

    return true;
  }

  Future<String> _foodImageUrlForFood(
    Map<String, dynamic>? food,
    String foodName,
  ) async {
    // Priority for manual search images:
    // 1) verified imageUrl already in CSV/API,
    // 2) Wikipedia page thumbnail,
    // 3) Wikimedia Commons image search,
    // 4) Openverse free image search,
    // 5) fallback restaurant icon.
    final existing = _firstAvailableImageUrl(food);
    if (existing.isNotEmpty) return existing;

    final query = _cleanFoodImageQuery(
      (food?['imageQuery'] ?? food?['name'] ?? foodName).toString(),
    );

    if (query.isEmpty) return '';

    final wiki = await _fetchWikipediaFoodImage(query);
    if (wiki.isNotEmpty) return wiki;

    final commons = await _fetchWikimediaCommonsFoodImage(query);
    if (commons.isNotEmpty) return commons;

    final openverse = await _fetchOpenverseFoodImage(query);
    if (openverse.isNotEmpty) return openverse;

    return '';
  }

  String _cleanFoodImageQuery(String value) {
    var q = value
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Keep image search focused on food, not nutrition labels/categories.
    q = q
        .replaceAll(RegExp(r'\bcalories?\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bkcal\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bgrams?\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return q;
  }

  Map<String, String> get _imageRequestHeaders => const {
    'Accept': 'application/json',
    'User-Agent': 'NutriPulse/1.0 (student health app)',
  };

  Future<String> _fetchWikipediaFoodImage(String query) async {
    try {
      final pageTitle = query
          .split(' ')
          .where((part) => part.trim().isNotEmpty)
          .map((part) => part[0].toUpperCase() + part.substring(1))
          .join(' ');

      final uri = Uri.parse(
        'https://en.wikipedia.org/api/rest_v1/page/summary/'
        '${Uri.encodeComponent(pageTitle)}',
      );

      final res = await http
          .get(uri, headers: _imageRequestHeaders)
          .timeout(const Duration(seconds: 4));

      if (res.statusCode != 200) return '';

      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) return '';

      final thumbnail = data['thumbnail'];
      if (thumbnail is Map<String, dynamic>) {
        final source = (thumbnail['source'] ?? '').toString();
        if (_isUsableImageUrl(source)) return source;
      }

      final original = data['originalimage'];
      if (original is Map<String, dynamic>) {
        final source = (original['source'] ?? '').toString();
        if (_isUsableImageUrl(source)) return source;
      }
    } catch (_) {}

    return '';
  }

  Future<String> _fetchWikimediaCommonsFoodImage(String query) async {
    try {
      final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
        'action': 'query',
        'generator': 'search',
        'gsrsearch': '$query food',
        'gsrnamespace': '6',
        'gsrlimit': '1',
        'prop': 'imageinfo',
        'iiprop': 'url',
        'iiurlwidth': '900',
        'format': 'json',
        'origin': '*',
      });

      final res = await http
          .get(uri, headers: _imageRequestHeaders)
          .timeout(const Duration(seconds: 4));

      if (res.statusCode != 200) return '';

      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) return '';

      final queryData = data['query'];
      if (queryData is! Map<String, dynamic>) return '';

      final pages = queryData['pages'];
      if (pages is! Map<String, dynamic> || pages.isEmpty) return '';

      for (final page in pages.values) {
        if (page is! Map<String, dynamic>) continue;
        final infos = page['imageinfo'];
        if (infos is! List || infos.isEmpty) continue;
        final first = infos.first;
        if (first is! Map<String, dynamic>) continue;

        final thumb = (first['thumburl'] ?? '').toString();
        if (_isUsableImageUrl(thumb)) return thumb;

        final url = (first['url'] ?? '').toString();
        if (_isUsableImageUrl(url)) return url;
      }
    } catch (_) {}

    return '';
  }

  Future<String> _fetchOpenverseFoodImage(String query) async {
    try {
      final uri = Uri.https('api.openverse.engineering', '/v1/images/', {
        'q': '$query food',
        'page_size': '1',
        'mature': 'false',
      });

      final res = await http
          .get(uri, headers: _imageRequestHeaders)
          .timeout(const Duration(seconds: 4));

      if (res.statusCode != 200) return '';

      final data = jsonDecode(res.body);
      if (data is! Map<String, dynamic>) return '';

      final results = data['results'];
      if (results is! List || results.isEmpty) return '';

      final first = results.first;
      if (first is! Map<String, dynamic>) return '';

      final thumbnail = (first['thumbnail'] ?? '').toString();
      if (_isUsableImageUrl(thumbnail)) return thumbnail;

      final url = (first['url'] ?? '').toString();
      if (_isUsableImageUrl(url)) return url;
    } catch (_) {}

    return '';
  }

  Widget _foodSearchThumbnail(Map<String, dynamic> food, String name) {
    final url = _firstAvailableImageUrl(food);

    if (url.isEmpty) {
      return Icon(Icons.restaurant_rounded, color: _lime);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.network(
        url,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        cacheWidth: 96,
        cacheHeight: 96,
        filterQuality: FilterQuality.low,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) =>
            Icon(Icons.restaurant_rounded, color: _lime),
      ),
    );
  }

  Widget _heroImage() {
    // Camera/gallery scan always shows the real snapped/selected image.
    if (_imageFile != null) {
      return Image.file(_imageFile!, fit: BoxFit.cover);
    }

    // Barcode and manual search use image URL.
    if (_barcodeImageUrl != null && _barcodeImageUrl!.trim().isNotEmpty) {
      final source = _barcodeImageUrl!.trim();

      if (source.startsWith('asset:')) {
        final assetPath = source.substring('asset:'.length);
        return Image.asset(
          assetPath,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _heroFallback(),
        );
      }

      if (source.startsWith('http://') || source.startsWith('https://')) {
        return Image.network(
          source,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _heroFallback();
          },
          errorBuilder: (_, __, ___) => _heroFallback(),
        );
      }
    }

    return _heroFallback();
  }

  Widget _heroFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _bgGradient,
        ),
      ),
      child: Center(
        child: Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            color: _lime.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.restaurant_rounded, color: _lime, size: 50),
        ),
      ),
    );
  }

  Widget _heroChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _lime, size: 13),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── Meal type selector ────────────────────────────────────────
  Widget _mealTypeSelector() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _mealTypes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (_, i) {
          final type = _mealTypes[i];
          final selected = _mealType == type;
          final label = type[0].toUpperCase() + type.substring(1);
          final icon = type == 'breakfast'
              ? Icons.wb_twilight_rounded
              : type == 'lunch'
              ? Icons.wb_sunny_rounded
              : type == 'dinner'
              ? Icons.nightlight_round
              : Icons.cookie_rounded;
          return GestureDetector(
            onTap: () {
              setState(() => _mealType = type);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: selected ? _lime : _surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: selected ? _lime : _hair),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: selected ? Colors.black : _soft),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: selected ? Colors.black : Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
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

  // ── Calorie ring + macro donut dashboard ──────────────────────
  Widget _calorieAndMacroDashboard({
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: _hair),
      ),
      child: Row(
        children: [
          // Animated calorie ring with counting number.
          Expanded(
            child: _CalorieRing(
              calories: calories,
              // a soft daily reference so the ring has meaning
              goal: 2000,
            ),
          ),
          const SizedBox(width: 14),
          // Animated macro split donut + legend.
          Expanded(
            child: _MacroDonut(
              protein: protein,
              carbs: carbs,
              fat: fat,
              colorProtein: _cProtein,
              colorCarbs: _cCarbs,
              colorFat: _cFat,
            ),
          ),
        ],
      ),
    );
  }

  // ── Macro bars (animated) ─────────────────────────────────────
  Widget _macroBarsCard({
    required double protein,
    required double carbs,
    required double fat,
    required double sugar,
  }) {
    final maxVal = [
      protein,
      carbs,
      fat,
      sugar,
      1.0,
    ].reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: _lime, size: 19),
              const SizedBox(width: 7),
              Text(
                'Macronutrients',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              Text(
                'per ${_portionG.round()}g',
                style: GoogleFonts.outfit(
                  color: _soft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _MacroBar(
            label: 'Protein',
            grams: protein,
            max: maxVal,
            color: _cProtein,
            icon: Icons.fitness_center_rounded,
          ),
          const SizedBox(height: 12),
          _MacroBar(
            label: 'Carbs',
            grams: carbs,
            max: maxVal,
            color: _cCarbs,
            icon: Icons.grain_rounded,
          ),
          const SizedBox(height: 12),
          _MacroBar(
            label: 'Fat',
            grams: fat,
            max: maxVal,
            color: _cFat,
            icon: Icons.water_drop_rounded,
          ),
          const SizedBox(height: 12),
          _MacroBar(
            label: 'Sugar',
            grams: sugar,
            max: maxVal,
            color: _cSugar,
            icon: Icons.cake_rounded,
          ),
        ],
      ),
    );
  }

  // ── Health gauge (animated arc) ───────────────────────────────
  Widget _healthGaugeCard(int score) {
    final label = score >= 80
        ? 'Excellent'
        : score >= 65
        ? 'Good'
        : score >= 50
        ? 'Moderate'
        : 'Heavy';
    final tone = score >= 65
        ? _lime
        : score >= 50
        ? _cCarbs
        : _cFat;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _hair),
      ),
      child: Row(
        children: [
          _HealthGauge(score: score, tone: tone),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.shield_moon_rounded, color: _lime, size: 18),
                    const SizedBox(width: 7),
                    Text(
                      'Health Score',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: tone.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: tone,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Based on calories, protein, sugar and fat for this portion.',
                  style: GoogleFonts.outfit(
                    color: _soft,
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Smart Nutrition Insight (AI advice — content preserved) ────
  Widget _smartNutritionInsightCard({
    required String foodName,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required double sugar,
  }) {
    final advice = _analyzeFoodAdvice(
      foodName: foodName,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      sugar: sugar,
    );

    final isHealthy = advice.level == _FoodAdviceLevel.healthy;
    final accent = isHealthy
        ? const Color(0xFF7CF0A9)
        : advice.level == _FoodAdviceLevel.warning
        ? const Color(0xFFFF8E6E)
        : const Color(0xFFFFD84D);
    final icon = isHealthy
        ? Icons.verified_rounded
        : advice.level == _FoodAdviceLevel.warning
        ? Icons.warning_amber_rounded
        : Icons.auto_awesome_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.14), accent.withOpacity(0.05)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  advice.title,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'AI',
                  style: GoogleFonts.outfit(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            advice.summary,
            style: GoogleFonts.outfit(
              color: Colors.white.withOpacity(0.82),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ...advice.reasons
              .take(2)
              .map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Icon(Icons.circle, size: 6, color: accent),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          item,
                          style: GoogleFonts.outfit(
                            color: Colors.white.withOpacity(0.74),
                            fontSize: 12.4,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  int _calculateFoodScore({
    required double calories,
    required double protein,
    required double sugar,
    required double fat,
  }) {
    var score = 72;

    if (protein >= 25) score += 12;
    if (protein >= 15 && protein < 25) score += 7;
    if (sugar > 25) score -= 15;
    if (sugar > 12 && sugar <= 25) score -= 8;
    if (calories > 800) score -= 12;
    if (calories < 550) score += 5;
    if (fat > 35) score -= 8;

    return score.clamp(35, 98);
  }

  // ── AI Portion Estimate (content preserved) ───────────────────
  Widget _portionEstimateCard() {
    final confidenceText =
        '${(_portionConfidence * 100).clamp(0, 100).toInt()}%';
    final subtitle = _barcode != null
        ? 'Packaged serving from label • editable'
        : _portionEstimated
        ? 'Estimated from your photo • editable'
        : 'Estimated serving • editable';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _lime.withOpacity(0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _PulseAIOrb(size: 44, iconSize: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI Portion Estimate',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(
                        color: _soft,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _lime.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  confidenceText,
                  style: GoogleFonts.outfit(
                    color: _lime,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Builder(
            builder: (_) {
              final foodName = (_nutrition?['name'] ?? 'food').toString();
              final unit = _portionUnitForFood(foodName, _nutrition);
              final quantity = _quantityForCurrentPortion(foodName);
              final label = quantity <= 1.0 ? unit.singular : unit.plural;
              final canMinus = quantity > unit.minUnits;
              final canPlus = quantity < unit.maxUnits;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _formatQuantity(quantity),
                        style: GoogleFonts.outfit(
                          color: _lime,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      _quantityStepButton(
                        icon: Icons.remove_rounded,
                        onTap: canMinus
                            ? () => setState(
                                () => _setPortionByQuantity(
                                  foodName,
                                  quantity - unit.step,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      _quantityStepButton(
                        icon: Icons.add_rounded,
                        onTap: canPlus
                            ? () => setState(
                                () => _setPortionByQuantity(
                                  foodName,
                                  quantity + unit.step,
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Normal serving: 1 ${unit.singular}. You can add more if you ate extra.',
                    style: GoogleFonts.outfit(
                      color: _soft.withOpacity(0.86),
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'AI-assisted estimate. Adjust the quantity if needed.',
            style: GoogleFonts.outfit(
              color: _soft.withOpacity(0.86),
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  // ── Advanced portion slider ───────────────────────────────────
  Widget _advancedPortionSlider() {
    final foodName = (_nutrition?['name'] ?? 'food').toString();
    final normalG = _normalServingGrams(foodName, _nutrition);
    final unit = _portionUnitForFood(foodName, _nutrition);
    final minG = unit.minUnits * unit.gramsPerUnit;
    final maxG = unit.maxUnits * unit.gramsPerUnit;
    final sliderValue = _portionG.clamp(minG, maxG).toDouble();
    final unitDivisions = math
        .max(1, ((unit.maxUnits - unit.minUnits) / unit.step).round())
        .toInt();
    final gramDivisions = math.max(1, ((maxG - minG) / 10).round()).toInt();

    _syncGramController();

    final currentUnitText = _formatPortionAmount(
      sliderValue,
      foodName,
      _nutrition,
    );
    final currentGramText = _formatGrams(sliderValue);
    final unitModeLabel = _portionUnitModeLabel(unit);
    final quickQuantities = <double>{
      1.0,
      2.0,
      3.0,
      unit.minUnits,
      unit.maxUnits > 4 ? 4.0 : unit.maxUnits,
    }.where((q) => q >= unit.minUnits && q <= unit.maxUnits).toList()..sort();

    final quickGrams = <double>{
      minG,
      normalG.clamp(minG, maxG).toDouble(),
      _snapToNearest((normalG * 1.5).clamp(minG, maxG).toDouble(), 10),
      _snapToNearest((normalG * 2).clamp(minG, maxG).toDouble(), 10),
      maxG,
    }.where((g) => g >= minG && g <= maxG).toList()..sort();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: _lime, size: 19),
              const SizedBox(width: 7),
              Text(
                'Portion size',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _lime.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _portionInputMode == _PortionInputMode.unit
                      ? currentUnitText
                      : currentGramText,
                  style: GoogleFonts.outfit(
                    color: _lime,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: _surface2,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: _hair),
            ),
            child: Row(
              children: [
                _portionModeTab(
                  label: unitModeLabel,
                  selected: _portionInputMode == _PortionInputMode.unit,
                  onTap: () => setState(
                    () => _portionInputMode = _PortionInputMode.unit,
                  ),
                ),
                _portionModeTab(
                  label: 'Grams',
                  selected: _portionInputMode == _PortionInputMode.grams,
                  onTap: () {
                    _syncGramController();
                    setState(() => _portionInputMode = _PortionInputMode.grams);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_portionInputMode == _PortionInputMode.unit) ...[
            Text(
              'Default input: ${unit.singular}. Change to grams only when you know the exact weight.',
              style: GoogleFonts.outfit(
                color: _soft,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 7,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
                activeTrackColor: _lime,
                inactiveTrackColor: Colors.white.withOpacity(0.08),
                thumbColor: _lime,
                overlayColor: _lime.withOpacity(0.18),
              ),
              child: Slider(
                value: sliderValue,
                min: minG,
                max: maxG,
                divisions: unitDivisions,
                onChanged: (v) {
                  setState(() {
                    final q = _snapQuantity(v / unit.gramsPerUnit, unit.step);
                    _setPortionByQuantity(foodName, q);
                  });
                },
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: quickQuantities.map((q) {
                final currentQ = _quantityForCurrentPortion(foodName);
                final selected = (currentQ - q).abs() < 0.05;
                final label = q <= 1.0 ? unit.singular : unit.plural;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _setPortionByQuantity(foodName, q));
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? _lime : _surface2,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: selected ? _lime : _hair),
                      ),
                      child: Text(
                        '${_formatQuantity(q)} $label',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: selected ? Colors.black : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ] else ...[
            Text(
              'Exact gram mode. This still saves the same meal, only the input method changes.',
              style: GoogleFonts.outfit(
                color: _soft,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _surface2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _hair),
                    ),
                    child: TextField(
                      controller: _gramController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        suffixText: 'g',
                        suffixStyle: GoogleFonts.outfit(
                          color: _lime,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      onChanged: (value) {
                        final parsed = double.tryParse(value);
                        if (parsed == null) return;
                        if (parsed < minG || parsed > maxG) return;
                        setState(() => _setPortionByGrams(foodName, parsed));
                      },
                      onSubmitted: (value) {
                        final parsed = double.tryParse(value);
                        if (parsed == null) {
                          _syncGramController();
                          return;
                        }
                        setState(() => _setPortionByGrams(foodName, parsed));
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _quantityStepButton(
                  icon: Icons.remove_rounded,
                  onTap: sliderValue > minG
                      ? () => setState(
                          () => _setPortionByGrams(foodName, sliderValue - 10),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                _quantityStepButton(
                  icon: Icons.add_rounded,
                  onTap: sliderValue < maxG
                      ? () => setState(
                          () => _setPortionByGrams(foodName, sliderValue + 10),
                        )
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 7,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
                activeTrackColor: _lime,
                inactiveTrackColor: Colors.white.withOpacity(0.08),
                thumbColor: _lime,
                overlayColor: _lime.withOpacity(0.18),
              ),
              child: Slider(
                value: sliderValue,
                min: minG,
                max: maxG,
                divisions: gramDivisions,
                onChanged: (v) {
                  setState(() => _setPortionByGrams(foodName, v));
                },
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: quickGrams.map((g) {
                final selected = (sliderValue - g).abs() < 5;
                return GestureDetector(
                  onTap: () => setState(() => _setPortionByGrams(foodName, g)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? _lime : _surface2,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: selected ? _lime : _hair),
                    ),
                    child: Text(
                      _formatGrams(g),
                      style: GoogleFonts.outfit(
                        color: selected ? Colors.black : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Text(
              'Also shown as: $currentUnitText',
              style: GoogleFonts.outfit(
                color: _lime.withOpacity(0.90),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _portionModeTab({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? _lime : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: selected ? Colors.black : _soft,
              fontSize: 12.2,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceInfoCard() {
    final source = _barcode != null
        ? 'Barcode scan'
        : _imageFile != null
        ? 'AI image recognition'
        : 'Manual search';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _hair),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: _soft, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$source • Nutrition values change based on your selected portion.',
              style: GoogleFonts.outfit(
                color: _soft,
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveButton() {
    return _GlowButton(
      label: _isSaving ? '' : 'Add to Log',
      icon: _isSaving ? null : Icons.add_rounded,
      loading: _isSaving,
      height: 58,
      big: true,
      onTap: _isSaving
          ? null
          : () {
              _saveMeal();
            },
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  ANIMATED / PAINTER HELPER WIDGETS
// ════════════════════════════════════════════════════════════════

class _FoodDatabaseSearchState {
  const _FoodDatabaseSearchState({
    this.results = const <Map<String, dynamic>>[],
    this.loading = false,
  });

  final List<Map<String, dynamic>> results;
  final bool loading;

  _FoodDatabaseSearchState copyWith({
    List<Map<String, dynamic>>? results,
    bool? loading,
  }) {
    return _FoodDatabaseSearchState(
      results: results ?? this.results,
      loading: loading ?? this.loading,
    );
  }
}

enum _EntryMethod { scan, barcode, manual }

enum _PortionInputMode { unit, grams }

const Color _kLime = Color(0xFFD6FF60);
const Color _kSoft = Color(0xFFB7C2A8);

/// Staggered entrance: fade + slide-up (matches the dashboard's _StaggeredItem).
class _Stagger extends StatefulWidget {
  const _Stagger({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<_Stagger>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    // Stagger: start this item's entrance after index * interval.
    final delay = Duration(milliseconds: 70 * widget.index);
    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Same approach as the dashboard's _StaggeredItem: a STABLE tree.
    // The child is wrapped in a RepaintBoundary that never changes shape, and
    // the entrance is a cheap Opacity + Transform.translate. When the animation
    // finishes, the AnimatedBuilder simply stops ticking — the widget tree is
    // never rebuilt or swapped, so scrolling stays perfectly smooth.
    final content = RepaintBoundary(child: widget.child);
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - t)),
            child: child,
          ),
        );
      },
      child: content,
    );
  }
}

/// Static AI orb — glow ring + sparkle. No animation controller, so it
/// never repaints after layout (was the main scroll-jank source).
class _PulseAIOrb extends StatelessWidget {
  const _PulseAIOrb({this.size = 60, this.iconSize = 28});
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        color: _kLime.withOpacity(0.12),
        border: Border.all(color: _kLime.withOpacity(0.32), width: 1.4),
      ),
      child: Icon(Icons.auto_awesome_rounded, color: _kLime, size: iconSize),
    );
  }
}

/// Static "AI Powered" badge (no shader, no controller).
class _ShimmerBadge extends StatelessWidget {
  const _ShimmerBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: _kLime.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded, color: _kLime, size: 13),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: _kLime,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Primary glowing CTA button with loading state.
class _GlowButton extends StatelessWidget {
  const _GlowButton({
    required this.label,
    this.icon,
    this.onTap,
    this.loading = false,
    this.height = 50,
    this.big = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;
  final double height;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: height,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFD6FF60), Color(0xFFAEEA32)],
          ),
          borderRadius: BorderRadius.circular(big ? 18 : 15),
          boxShadow: [
            BoxShadow(
              color: _kLime.withOpacity(0.28),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.black,
                    strokeWidth: 2.6,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        color: Colors.black,
                        fontSize: big ? 16.5 : 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (icon != null) ...[
                      const SizedBox(width: 8),
                      Icon(icon, color: Colors.black, size: big ? 21 : 19),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// Animated calorie ring with a counting number in the middle.
class _CalorieRing extends StatelessWidget {
  const _CalorieRing({required this.calories, required this.goal});
  final double calories;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final pct = (calories / goal).clamp(0.0, 1.0);
    // Painted once and isolated as its own raster layer — no repaint on scroll.
    return RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _RingPainter(pct),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  calories.round().toString(),
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'kcal',
                  style: GoogleFonts.outfit(
                    color: _kLime,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 9;
    const stroke = 11.0;

    final bg = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bg);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = 2 * math.pi * progress;
    final fg = Paint()
      ..shader = const SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [Color(0xFFAEEA32), Color(0xFFD6FF60), Color(0xFFCCFF00)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}

/// Animated macro distribution donut with legend.
class _MacroDonut extends StatelessWidget {
  const _MacroDonut({
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.colorProtein,
    required this.colorCarbs,
    required this.colorFat,
  });

  final double protein, carbs, fat;
  final Color colorProtein, colorCarbs, colorFat;

  @override
  Widget build(BuildContext context) {
    final total = (protein + carbs + fat);
    final p = total == 0 ? 0.0 : protein / total;
    final c = total == 0 ? 0.0 : carbs / total;
    final f = total == 0 ? 0.0 : fat / total;

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 92,
            width: 92,
            child: CustomPaint(
              painter: _DonutPainter(
                p: p,
                c: c,
                f: f,
                t: 1.0,
                cP: colorProtein,
                cC: colorCarbs,
                cF: colorFat,
              ),
              child: Center(
                child: Text(
                  'Macros',
                  style: GoogleFonts.outfit(
                    color: _kSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _legendRow('Protein', colorProtein),
          const SizedBox(height: 4),
          _legendRow('Carbs', colorCarbs),
          const SizedBox(height: 4),
          _legendRow('Fat', colorFat),
        ],
      ),
    );
  }

  Widget _legendRow(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.white.withOpacity(0.78),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.p,
    required this.c,
    required this.f,
    required this.t,
    required this.cP,
    required this.cC,
    required this.cF,
  });
  final double p, c, f, t;
  final Color cP, cC, cF;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 7;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const stroke = 13.0;
    const gap = 0.06;

    final track = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, track);

    double start = -math.pi / 2;
    void seg(double frac, Color color) {
      if (frac <= 0) return;
      final sweep = (2 * math.pi * frac - gap) * t;
      if (sweep <= 0) return;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start + gap / 2, sweep, false, paint);
      start += 2 * math.pi * frac;
    }

    seg(p, cP);
    seg(c, cC);
    seg(f, cF);
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.t != t || old.p != p || old.c != c || old.f != f;
}

/// Animated horizontal macro bar.
class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.label,
    required this.grams,
    required this.max,
    required this.color,
    required this.icon,
  });

  final String label;
  final double grams;
  final double max;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final frac = (grams / (max == 0 ? 1 : max)).clamp(0.0, 1.0);
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(0.16),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: Colors.white.withOpacity(0.85),
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${grams.toStringAsFixed(1)}g',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Stack(
                  children: [
                    Container(height: 8, color: Colors.white.withOpacity(0.07)),
                    FractionallySizedBox(
                      widthFactor: frac,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color.withOpacity(0.7), color],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Animated semicircular health gauge.
class _HealthGauge extends StatelessWidget {
  const _HealthGauge({required this.score, required this.tone});
  final int score;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final v = score / 100;
    return RepaintBoundary(
      child: SizedBox(
        width: 84,
        height: 84,
        child: CustomPaint(
          painter: _GaugePainter(v, tone),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  score.toString(),
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                Text(
                  '/100',
                  style: GoogleFonts.outfit(
                    color: _kSoft,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.progress, this.tone);
  final double progress;
  final Color tone;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bg = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi * 0.75, math.pi * 1.5, false, bg);

    final fg = Paint()
      ..shader = SweepGradient(
        startAngle: math.pi * 0.75,
        endAngle: math.pi * 0.75 + math.pi * 1.5,
        colors: [tone.withOpacity(0.6), tone],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi * 0.75, math.pi * 1.5 * progress, false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) =>
      old.progress != progress || old.tone != tone;
}

class _PortionUnitData {
  const _PortionUnitData({
    required this.singular,
    required this.plural,
    required this.gramsPerUnit,
    required this.step,
    required this.minUnits,
    required this.maxUnits,
  });

  final String singular;
  final String plural;
  final double gramsPerUnit;
  final double step;
  final double minUnits;
  final double maxUnits;
}

class _PortionEstimate {
  const _PortionEstimate({
    required this.grams,
    required this.size,
    required this.confidence,
    required this.estimated,
  });
  final double grams;
  final String size;
  final double confidence;
  final bool estimated;
}

enum _FoodAdviceLevel { healthy, caution, warning }

class _FoodAdviceResult {
  final _FoodAdviceLevel level;
  final String title;
  final String summary;
  final List<String> reasons;
  final List<String> advice;

  const _FoodAdviceResult({
    required this.level,
    required this.title,
    required this.summary,
    required this.reasons,
    required this.advice,
  });
}

class _PremiumAnalyzeTimeline extends StatefulWidget {
  const _PremiumAnalyzeTimeline({super.key, this.image});

  /// The photo the user scanned/uploaded. When null (barcode or manual
  /// entry) the timeline falls back to the sparkle hero icon.
  final File? image;

  @override
  State<_PremiumAnalyzeTimeline> createState() =>
      _PremiumAnalyzeTimelineState();
}

class _PremiumAnalyzeTimelineState extends State<_PremiumAnalyzeTimeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  int get _step {
    final v = _controller.value;
    if (v < 0.34) return 0;
    if (v < 0.68) return 1;
    return 2;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _segmentProgress(double start, double end) {
    final raw = ((_controller.value - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeInOutCubic.transform(raw);
  }

  @override
  Widget build(BuildContext context) {
    const lime = Color(0xFFCCFF00);
    const soft = Color(0xFF888888);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final step = _step;
        final progress = _controller.value;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            widget.image != null
                ? _AnalyzePhotoHero(image: widget.image!, progress: progress)
                : _AnalyzeHeroIcon(progress: progress),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.18),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                step == 0
                    ? 'Analyzing food'
                    : step == 1
                    ? 'Getting nutrition facts'
                    : 'Preparing your result',
                key: ValueKey(step),
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 24,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.35,
                ),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: Text(
                step == 0
                    ? (widget.image != null
                          ? 'Recognising the food in your photo'
                          : 'Recognising the food from your scan')
                    : step == 1
                    ? 'Calculating calories, protein, carbs and fat'
                    : 'Building a clean macro summary for you',
                key: ValueKey('subtitle-$step'),
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: soft.withOpacity(0.82),
                  fontSize: 13.2,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.clamp(0.06, 1.0),
                minHeight: 7,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: const AlwaysStoppedAnimation<Color>(lime),
              ),
            ),
            const SizedBox(height: 22),
            _AnalyzeStepRow(
              title: 'Analyzing food',
              subtitle: 'Food type and confidence',
              state: step > 0
                  ? _AnalyzeStepState.done
                  : _AnalyzeStepState.active,
              progress: _segmentProgress(0.00, 0.34),
            ),
            const SizedBox(height: 12),
            _AnalyzeStepRow(
              title: 'Getting nutrition facts',
              subtitle: 'Calories and macros',
              state: step > 1
                  ? _AnalyzeStepState.done
                  : step == 1
                  ? _AnalyzeStepState.active
                  : _AnalyzeStepState.pending,
              progress: _segmentProgress(0.34, 0.68),
            ),
            const SizedBox(height: 12),
            _AnalyzeStepRow(
              title: 'Preparing result',
              subtitle: 'Final food card',
              state: step == 2
                  ? _AnalyzeStepState.active
                  : _AnalyzeStepState.pending,
              progress: _segmentProgress(0.68, 1.00),
            ),
          ],
        );
      },
    );
  }
}

enum _AnalyzeStepState { pending, active, done }

class _AnalyzeStepRow extends StatelessWidget {
  const _AnalyzeStepRow({
    required this.title,
    required this.subtitle,
    required this.state,
    required this.progress,
  });

  final String title;
  final String subtitle;
  final _AnalyzeStepState state;
  final double progress;

  @override
  Widget build(BuildContext context) {
    const lime = Color(0xFFCCFF00);
    const soft = Color(0xFF888888);

    final isDone = state == _AnalyzeStepState.done;
    final isActive = state == _AnalyzeStepState.active;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isActive
            ? lime.withOpacity(0.115)
            : Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive
              ? lime.withOpacity(0.35)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          _AnalyzeStatusIcon(state: state, progress: progress),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: isActive || isDone
                        ? Colors.white
                        : soft.withOpacity(0.62),
                    fontSize: 13.6,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: soft.withOpacity(isActive || isDone ? 0.86 : 0.50),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (isDone)
            Text(
              'Done',
              style: GoogleFonts.outfit(
                color: lime,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
    );
  }
}

class _AnalyzeStatusIcon extends StatelessWidget {
  const _AnalyzeStatusIcon({required this.state, required this.progress});

  final _AnalyzeStepState state;
  final double progress;

  @override
  Widget build(BuildContext context) {
    const lime = Color(0xFFCCFF00);

    if (state == _AnalyzeStepState.done) {
      return Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(color: lime, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: Colors.black, size: 21),
      );
    }

    if (state == _AnalyzeStepState.pending) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Icon(
          Icons.more_horiz_rounded,
          color: Colors.white.withOpacity(0.34),
          size: 20,
        ),
      );
    }

    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress.clamp(0.12, 0.95),
            strokeWidth: 3,
            backgroundColor: Colors.white.withOpacity(0.09),
            valueColor: const AlwaysStoppedAnimation<Color>(lime),
          ),
          const Icon(Icons.auto_awesome_rounded, color: lime, size: 15),
        ],
      ),
    );
  }
}

class _AnalyzeHeroIcon extends StatelessWidget {
  const _AnalyzeHeroIcon({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    const lime = Color(0xFFCCFF00);
    final pulse =
        0.96 + (0.04 * Curves.easeInOut.transform((progress * 3) % 1));

    return Transform.scale(
      scale: pulse,
      child: Container(
        width: 82,
        height: 82,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              lime.withOpacity(0.22),
              lime.withOpacity(0.08),
              Colors.transparent,
            ],
          ),
        ),
        child: Center(
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: lime.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: lime.withOpacity(0.34)),
              boxShadow: [
                BoxShadow(
                  color: lime.withOpacity(0.18),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: lime,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the user's uploaded/scanned photo inside the analyzing screen with a
/// sweeping scan-line and a soft lime glow ring, instead of the generic icon.
class _AnalyzePhotoHero extends StatelessWidget {
  const _AnalyzePhotoHero({required this.image, required this.progress});

  final File image;
  final double progress;

  @override
  Widget build(BuildContext context) {
    const lime = Color(0xFFCCFF00);

    // Sweep the scan line up and down across the photo.
    final sweep = Curves.easeInOut.transform((progress * 2) % 1);
    final pulse =
        0.97 + (0.03 * Curves.easeInOut.transform((progress * 3) % 1));

    return Transform.scale(
      scale: pulse,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              lime.withOpacity(0.20),
              lime.withOpacity(0.06),
              Colors.transparent,
            ],
          ),
        ),
        child: Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: lime.withOpacity(0.45), width: 2),
            boxShadow: [
              BoxShadow(
                color: lime.withOpacity(0.18),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipOval(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  image,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => Container(
                    color: lime.withOpacity(0.12),
                    child: const Icon(
                      Icons.restaurant_rounded,
                      color: lime,
                      size: 30,
                    ),
                  ),
                ),
                // Subtle darken so the lime scan line reads clearly.
                Container(color: Colors.black.withOpacity(0.18)),
                // Sweeping scan line.
                Align(
                  alignment: Alignment(0, (sweep * 2) - 1),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          lime.withOpacity(0.95),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(color: lime.withOpacity(0.6), blurRadius: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
