/// Resolves a display image URL for a given make + model.
/// Uses the free imagin.studio CDN for realistic car renders.
/// Falls back to the bundled default hero asset.
abstract final class CarImageService {
  static const _defaultAsset = 'assets/logo/car_default_hero.png';

  static const _customer = 'hrjavascript-masede';

  /// Returns a network URL for a specific make/model render.
  /// Maps Indian brand names to their international equivalents
  /// so the CDN can resolve the correct car images.
  static String _normalizeMake(String make) => switch (make) {
        'Maruti Suzuki' => 'Suzuki',
        'Škoda' => 'Skoda',
        _ => make,
      };

  static String imageUrl({
    required String make,
    required String model,
    int year = 2024,
    String angle = '23',
    String paintId = 'pspc0001',
  }) {
    final cdnMake = _normalizeMake(make);
    final encodedMake = Uri.encodeComponent(cdnMake);
    final encodedModel = Uri.encodeComponent(model);
    return 'https://cdn.imagin.studio/getimage'
        '?customer=$_customer'
        '&make=$encodedMake'
        '&modelFamily=$encodedModel'
        '&modelYear=$year'
        '&angle=$angle'
        '&paintId=$paintId'
        '&width=800';
  }

  static String get defaultAsset => _defaultAsset;

  /// Brand-accent color for hero gradient tinting.
  static int brandTint(String make) => switch (make.toLowerCase()) {
        'maruti suzuki' => 0xFF1A3F7D,
        'mahindra' => 0xFFD52B1E,
        'tata' => 0xFF0A4C8E,
        'force' => 0xFF2E7D32,
        'mg' => 0xFFCC0000,
        'byd' => 0xFF1A8C37,
        'isuzu' => 0xFFB71C1C,
        'ashok leyland' => 0xFF1565C0,
        'datsun' => 0xFF1A237E,
        'bmw' => 0xFF1C69D4,
        'mercedes-benz' => 0xFF9E9E9E,
        'audi' => 0xFFBB0A1E,
        'toyota' => 0xFFEB0A1E,
        'honda' => 0xFFCC0000,
        'hyundai' => 0xFF002C5F,
        'ford' => 0xFF003478,
        'tesla' => 0xFFCC0000,
        'volkswagen' => 0xFF001E50,
        'kia' => 0xFF05141F,
        'nissan' => 0xFFC3002F,
        'renault' => 0xFFFFCC00,
        'škoda' => 0xFF4BA82E,
        'porsche' => 0xFFB12B28,
        'ferrari' => 0xFFDC0000,
        'lamborghini' => 0xFFD9A41E,
        'chevrolet' => 0xFFD4A843,
        'jeep' => 0xFF3A5729,
        'jaguar' => 0xFF1B5E20,
        'land rover' => 0xFF2E7D32,
        'lexus' => 0xFF1A1A1A,
        'volvo' => 0xFF003057,
        'mazda' => 0xFF910F19,
        'subaru' => 0xFF013C74,
        'suzuki' => 0xFF00458D,
        'fiat' => 0xFF8B0000,
        'mitsubishi' => 0xFFCC0000,
        _ => 0xFF009DFF,
      };
}
