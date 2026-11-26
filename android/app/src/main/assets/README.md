# أصول Android المضمّنة

يبقى ملفا PRoot الصغيران داخل APK الشامل، بينما **لا توجد أي ملفات RootFS لـ Arch Linux داخل السورس أو داخل APK**.

| ABI | PRoot المضمّن | ملف RootFS الخارجي | مصدر التنزيل |
|---|---|---|---|
| `arm64-v8a` | `bin/arm64-v8a/proot` | `arch-aarch64.tar` | GitHub Release `arch-rootfs-v010` |
| `armeabi-v7a` | `bin/armeabi-v7a/proot` | `arch-armv7.tar` | GitHub Release `arch-rootfs-v010` |

عند الضغط على «تنزيل وإعداد Arch»، يختار التطبيق ABI المدعوم، ثم ينزّل الأرشيف المقابل إلى `files/downloads/rootfs/` داخل مساحة التطبيق، ويتحقق من SHA-256 المحدد في `rootfs-release-manifest.json` و`RootfsDownloadManager.kt`. بعدها يستخرج محتوى الأرشيف إلى `files/arch/<abi>/`، وهو المسار الذي يستخدمه PRoot. يُحذف الأرشيف المؤقت بعد اكتمال التثبيت بنجاح.

لا تُحمّل أصول ARM64 على جهاز ARM32 أو العكس. يحتفظ التطبيق ببيئة Arch المستخرجة محلياً، لذلك لا يحتاج تشغيل الجلسات اللاحقة إلى تنزيل جديد.
