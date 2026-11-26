# Arch Terminal

تطبيق طرفية محلي مبني باستخدام Flutter لأجهزة Android وLinux وWindows، مع بيئة Arch Linux محلية وإدارة RootFS ودعم جلسات الطرفية وميزات مساعدة اختيارية.

## المتطلبات

- Flutter SDK المتوافق مع Dart `^3.13.0`
- Android SDK وJava 21 لبناء Android
- اتصال بالإنترنت عند جلب حزم Flutter وملفات RootFS المطلوبة للتثبيت الأولي

## التشغيل محليًا

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

لبناء نسخة Android تجريبية:

```bash
flutter build apk --release
```

تُبنى نسخة APK تلقائيًا عبر GitHub Actions عند الدفع إلى `main` أو عند تشغيل سير عمل البناء يدويًا. النسخة الحالية هي `1.0.0+106`.

## بنية المشروع

- `lib/`: واجهة التطبيق ومنطق الطرفية وإدارة الجلسات.
- `android/`: تكامل Android وخدمات التثبيت والتشغيل في الخلفية.
- `packages/xterm/`: حزمة الطرفية المحلية المضمنة.
- `test/`: اختبارات Flutter.
- `docs/`: توثيق التسليم وتصميم الواجهة وسلوك RootFS.

راجع [POLICY.md](POLICY.md) لقواعد المساهمة والنشر.
