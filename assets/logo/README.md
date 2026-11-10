# FixEase Logo Assets

Add these files to this folder:

- `wrench_logo.png`  
  Use the wrench image you provided as the brand logo.

- `add_vehicle_icon.png`  
  Add-vehicle / default fallback when no car photo is set.

- `car_hero_reference.png`  
  Optional hero image for the home header (matches reference UI).

- `car_placeholder.png` (optional legacy)  
  Not required if you use `add_vehicle_icon.png` everywhere.

Recommended format:

- PNG
- Square image
- At least 1024x1024 for logo quality on splash/app icon

After Flutter SDK is installed, run:

```bash
flutter pub get
dart run flutter_native_splash:create
dart run flutter_launcher_icons
flutter run
```
