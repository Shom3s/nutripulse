import 'package:cloud_firestore/cloud_firestore.dart';

class MarketItem {
  const MarketItem({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    this.sellerPhotoBase64 = '',
    required this.name,
    required this.description,
    required this.category,
    required this.price,
    required this.quantity,
    required this.location,
    required this.healthTag,
    this.imageBase64 = '',
    this.expiryDate = '',
    this.status = 'active',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String sellerId;
  final String sellerName;
  final String sellerPhotoBase64;
  final String name;
  final String description;
  final String category;
  final double price;
  final int quantity;
  final String location;
  final String healthTag;
  final String imageBase64;
  final String expiryDate;
  final String status;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  bool get isActive => status == 'active' && quantity > 0;
  bool get hasImage => imageBase64.trim().isNotEmpty;

  factory MarketItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return MarketItem(
      id: doc.id,
      sellerId: (data['sellerId'] ?? '').toString(),
      sellerName: (data['sellerName'] ?? 'NutriPulse Seller').toString(),
      sellerPhotoBase64: (data['sellerPhotoBase64'] ?? '').toString(),
      name: (data['name'] ?? 'Food item').toString(),
      description: (data['description'] ?? '').toString(),
      category: (data['category'] ?? 'Food').toString(),
      price: _toDouble(data['price']),
      quantity: _toInt(data['quantity']),
      location: (data['location'] ?? 'COD pickup').toString(),
      healthTag: (data['healthTag'] ?? 'Community food').toString(),
      imageBase64: (data['imageBase64'] ?? '').toString(),
      expiryDate: (data['expiryDate'] ?? '').toString(),
      status: (data['status'] ?? 'active').toString(),
      createdAt: data['createdAt'] is Timestamp
          ? data['createdAt'] as Timestamp
          : null,
      updatedAt: data['updatedAt'] is Timestamp
          ? data['updatedAt'] as Timestamp
          : null,
    );
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'sellerId': sellerId,
      'sellerName': sellerName,
      'sellerPhotoBase64': sellerPhotoBase64,
      'name': name.trim(),
      'description': description.trim(),
      'category': category.trim(),
      'price': price,
      'quantity': quantity,
      'location': location.trim(),
      'healthTag': healthTag.trim(),
      'imageBase64': imageBase64,
      'expiryDate': expiryDate.trim(),
      'status': status,
      'paymentMethod': 'COD',
      'codOnly': true,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
