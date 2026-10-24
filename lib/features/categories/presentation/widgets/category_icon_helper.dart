import 'package:flutter/material.dart';

class CategoryIconHelper {
  static const Map<String, IconData> iconMap = {
    // Expense & Living
    'shopping_cart': Icons.shopping_cart_rounded,
    'shopping_bag': Icons.shopping_bag_rounded,
    'restaurant': Icons.restaurant_rounded,
    'fastfood': Icons.fastfood_rounded,
    'local_cafe': Icons.local_cafe_rounded,
    'local_bar': Icons.local_bar_rounded,
    'local_gas_station': Icons.local_gas_station_rounded,
    'directions_car': Icons.directions_car_rounded,
    'two_wheeler': Icons.two_wheeler_rounded,
    'flight': Icons.flight_rounded,
    'directions_bus': Icons.directions_bus_rounded,
    'home_repair_service': Icons.home_repair_service_rounded,
    'home': Icons.home_rounded,
    'bolt': Icons.bolt_rounded,
    'water_drop': Icons.water_drop_rounded,
    'wifi': Icons.wifi_rounded,
    'medical_services': Icons.medical_services_rounded,
    'local_pharmacy': Icons.local_pharmacy_rounded,
    'family_restroom': Icons.family_restroom_rounded,
    'child_care': Icons.child_care_rounded,
    'movie': Icons.movie_rounded,
    'sports_esports': Icons.sports_esports_rounded,
    'fitness_center': Icons.fitness_center_rounded,
    'school': Icons.school_rounded,
    'book': Icons.menu_book_rounded,
    'pets': Icons.pets_rounded,
    'checkroom': Icons.checkroom_rounded,
    'more_horiz': Icons.more_horiz_rounded,

    // Income & Finance
    'payments': Icons.payments_rounded,
    'account_balance_wallet': Icons.account_balance_wallet_rounded,
    'account_balance': Icons.account_balance_rounded,
    'savings': Icons.savings_rounded,
    'trending_up': Icons.trending_up_rounded,
    'card_giftcard': Icons.card_giftcard_rounded,
    'work': Icons.work_rounded,
    'monetization_on': Icons.monetization_on_rounded,
    'receipt_long': Icons.receipt_long_rounded,
  };

  static const List<int> palette = [
    0xFF10B981, // Emerald Green
    0xFF059669, // Forest Green
    0xFFF59E0B, // Amber Orange
    0xFFD97706, // Deep Amber
    0xFFEF4444, // Crimson Red
    0xFFDC2626, // Scarlet
    0xFF8B5CF6, // Purple
    0xFF7C3AED, // Violet
    0xFFEC4899, // Pink
    0xFFDB2777, // Rose
    0xFF3B82F6, // Vibrant Blue
    0xFF2563EB, // Royal Blue
    0xFF06B6D4, // Cyan
    0xFF0891B2, // Teal-Blue
    0xFFF97316, // Orange
    0xFFEA580C, // Rust
    0xFF6366F1, // Indigo
    0xFF4F46E5, // Deep Indigo
    0xFF14B8A6, // Teal
    0xFF0D9488, // Dark Teal
    0xFF64748B, // Slate Gray
    0xFF475569, // Deep Slate
  ];

  static IconData getIcon(String? iconKey) {
    if (iconKey == null) return Icons.category_rounded;
    return iconMap[iconKey] ?? Icons.category_rounded;
  }
}
