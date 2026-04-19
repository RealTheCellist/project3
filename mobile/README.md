# Sumpyo Mobile (Flutter)

## Run
```powershell
flutter pub get
flutter run
```

## Quality checks
```powershell
flutter analyze
flutter test
```

## Android release build
1. Copy `android/key.properties.example` -> `android/key.properties`.
2. Set real keystore values in `key.properties`.
3. Build APK:
```powershell
flutter build apk --release
```
4. Build AAB:
```powershell
flutter build appbundle --release
```

Output paths:
- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

## Windows note
If plugin build fails with symlink messages, enable Developer Mode:
```powershell
start ms-settings:developers
```

