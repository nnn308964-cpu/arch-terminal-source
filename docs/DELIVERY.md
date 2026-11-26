# تقرير التسليم — Arch Terminal v010

## النتيجة

يقدّم المشروع تطبيق Flutter بواجهة مشتركة لأنظمة Android وLinux وWindows، مع بناء Android فقط في الإصدار الحالي. لا توجد قاعدة بيانات أو حسابات أو خادم تطبيقات أو مزامنة. يتصل تطبيق Android بالإنترنت **مرة واحدة عند الإعداد الأول** فقط لتنزيل ملف Arch Linux المناسب لمعمارية الهاتف من GitHub Releases العامة؛ وبعد التثبيت تبقى جلسة الطرفية وPRoot وRootFS محلية بالكامل.

| المجال | النتيجة الحالية |
|---|---|
| Flutter / Dart | 3.47.0 / 3.13.0 |
| واجهة الطرفية | xterm 4.0.0 |
| PTY | kyroon_pty 1.0.6 |
| APK Android | APK شامل واحد يدعم `arm64-v8a` و`armeabi-v7a` |
| حجم APK Release | 46.7 MB |
| PRoot | مضمّن داخل APK للمعماريتين |
| Arch RootFS | GitHub Release عام؛ يُنزّل حسب ABI عند التشغيل الأول |
| التحقق | SHA-256 مثبّت داخل التطبيق قبل الاستخراج |
| العربية والإيموجي | UTF-8 streaming وخطوط fallback مناسبة مع شبكة ANSI LTR |
| واجهة التحكم | شاشة طرفية داكنة مع لوحة أوامر جانبية تفتح بزر `<` |
| الإعداد بالخلفية | خدمة Android أمامية مع إشعار تقدم للتنزيل والتحقق والاستخراج |
| تحسين البطارية | خيار داخل لوحة الأوامر لطلب استثناء التطبيق من تحسين البطارية |
| حفظ RootFS | إعداد يختار بين التخزين الداخلي أو التخزين العام المستمر |

## آلية الإعداد الأول

يقرأ التطبيق قائمة ABI التي يوفرها Android ويختار أول قيمة مدعومة من `arm64-v8a` أو `armeabi-v7a`. بعدها ينزّل حصراً ملف RootFS المطابق من إصدار `arch-rootfs-v010` العام، ويحسب SHA-256 للملف المحمّل قبل أن يسمح باستخراجه إلى مساحة التطبيق الداخلية. عند فشل الاتصال أو التحقق، لا يستخرج التطبيق أي ملف جزئي ولا يعتبر Arch مثبتاً.

| ABI | ملف RootFS المنشور | SHA-256 |
|---|---|---|
| `arm64-v8a` | `arch-aarch64.tar` | `42a4eeaa038994ffd31fa173256ef2f0ef511358eeb41b9ea1f8626391b9b319` |
| `armeabi-v7a` | `arch-armv7.tar` | `ebe0fa119dea45e3af0aa61785676bdbf417bc5f754d529b87255dbf0ca4e3f0` |

> في الوضع الافتراضي «التخزين الداخلي»، يحذف التطبيق الأرشيف بعد اكتمال الاستخراج. أما عند اختيار «التخزين العام المستمر» من لوحة الأوامر، يحتفظ التطبيق بالأرشيف المتحقق منه في `/storage/emulated/0/ArchTerminal/rootfs/`. يبقى هذا الأرشيف بعد حذف التطبيق؛ وعند إعادة تثبيت التطبيق يتحقق من SHA-256 ويعيد استعماله دون تنزيل جديد، ثم يعيد استخراج البيئة الخاصة بالتطبيق.

## المستودع العام للأصول

المستودع [`arch-terminal-source`](https://github.com/nnn308964-cpu/arch-terminal-source) أصبح عاماً ويحتوي على Release لأصول RootFS فقط. لا يُنشر فيه سورس التطبيق أو ملفات APK. أُضيفت سياسة وGitHub Action لحظر امتدادات السورس وأرشيفات المشروع وAPK، وفُرضت حماية على الفرع `main` تتطلب نجاح هذا الفحص قبل التحديث.

## الواجهة والاستمرارية بالخلفية

تحتفظ شاشة الطرفية بمساحة التنفيذ أساساً، بينما تفتح أوامر التشغيل والإيقاف والتنزيل وإذن الملفات من لوحة جانبية. يعرض شريط الحالة إشارات PRoot وArch والبطارية، وتعرض بطاقة الإعداد نسبة تنزيل RootFS والحجم المنقول والسرعة ومراحل التحقق والاستخراج. تنقل خدمة Android الأمامية هذه الحالة إلى إشعار نظام مستمر، ولذلك يستمر الإعداد عند انتقال التطبيق إلى الخلفية ما دام Android يسمح بالخدمة.

يمكن للمستخدم اختيار «السماح بالعمل دون تحسين البطارية» من لوحة الأوامر. يفتح ذلك شاشة نظام Android الخاصة بالتطبيق؛ لا يعطّل التطبيق تحسين البطارية من تلقاء نفسه، بل يحتاج موافقة المستخدم الصريحة.

تتيح شاشة «إعداد حفظ Arch» في لوحة الأوامر اختيار «الحفظ الداخلي الخاص بالتطبيق» أو «الحفظ العام المستمر». تعرض الشاشة المسار الفعلي وأمر `cd` الخاص به مع زر نسخه. يفتح أمر «وصول الملفات» مجلد RootFS عندما يسمح Android بذلك، أو يفتح شاشة منح إذن التخزين عند الحاجة.

## الملفات الأساسية

التغييرات الرئيسية موجودة في `android/app/src/main/kotlin/com/example/arch_terminal/terminal/RootfsDownloadManager.kt` لتنزيل RootFS والتحقق منه وإصدار التقدم، و`ArchInstaller.kt` لاستخراج ملف جرى التحقق منه، و`ArchSetupService.kt` لتشغيل الإعداد في الخلفية، و`MainActivity.kt` لجسر Flutter وإذن الطاقة. يضم `android/app/src/main/assets/bin/` نسختي PRoot، بينما لم تعد ملفات RootFS جزءاً من حزمة APK.

## أوامر البناء والتحقق

```bash
flutter analyze
flutter test
tools/verify_android_assets.sh
flutter build apk --release
```

الملف الناتج هو `build/app/outputs/flutter-apk/app-release.apk`. تم التحقق من احتوائه على نسختي PRoot وعدم احتوائه على `arch-aarch64.tar` أو `arch-armv7.tar`.

## ملاحظات النشر

نسخة Release الحالية موقعة بمفتاح debug المخصص للاختبار. قبل النشر النهائي للمستخدمين يلزم ضبط keystore خاص بالإصدار وعدم مشاركة مفاتيحه. يظل دعم Linux وWindows في السورس للتطوير، ولا يتم بناء حزم لهما ضمن هذا التسليم.

## المراجع

[1]: https://github.com/nnn308964-cpu/arch-terminal-source/releases/tag/arch-rootfs-v010 "Arch Linux RootFS v010"
[2]: https://developer.android.com/training/data-storage/manage-all-files "Android manage all files"
[3]: https://pub.dev/packages/kyroon_pty "kyroon_pty 1.0.6"
[4]: https://pub.dev/packages/xterm/versions "xterm 4.0.0"
[5]: https://developer.android.com/develop/background-work/services/foreground-services "Android foreground services"
[6]: https://developer.android.com/training/monitoring-device-state/doze-standby "Android battery optimization"
