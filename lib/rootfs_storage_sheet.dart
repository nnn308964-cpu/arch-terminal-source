import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RootfsStorageSheet extends StatefulWidget {
  const RootfsStorageSheet({
    super.key,
    required this.initial,
    required this.arabicUi,
    required this.onSelect,
    required this.onRequestPermission,
    required this.onOpenLocation,
  });

  final Map<String, Object?> initial;
  final bool arabicUi;
  final Future<Map<String, Object?>> Function(String mode) onSelect;
  final Future<void> Function() onRequestPermission;
  final Future<Map<String, Object?>> Function() onOpenLocation;

  @override
  State<RootfsStorageSheet> createState() => _RootfsStorageSheetState();
}

class _RootfsStorageSheetState extends State<RootfsStorageSheet> {
  late Map<String, Object?> details = widget.initial;
  bool changing = false;

  bool get persistent => details['rootfsStoragePersistent'] == true;
  bool get ready => details['rootfsStorageReady'] == true;
  String get path => details['rootfsStoragePath']?.toString() ?? 'غير متاح';
  String get command =>
      details['rootfsStorageCommand']?.toString() ?? "cd '$path'";
  String _t(String arabic, String english) =>
      widget.arabicUi ? arabic : english;

  Future<void> _select(String mode) async {
    setState(() => changing = true);
    try {
      final updated = await widget.onSelect(mode);
      if (mounted) setState(() => details = updated);
    } finally {
      if (mounted) setState(() => changing = false);
    }
  }

  Future<void> _allowStorage() async {
    await widget.onRequestPermission();
  }

  Future<void> _openLocation() async {
    final updated = await widget.onOpenLocation();
    if (mounted) {
      setState(() => details = <String, Object?>{...details, ...updated});
    }
  }

  Future<void> _copyCommand() async {
    await Clipboard.setData(ClipboardData(text: command));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'تم نسخ أمر الوصول إلى الحافظة.',
              'Access command copied to clipboard.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF506174),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              const Icon(Icons.save_alt_outlined, color: Color(0xFF62D5FF)),
              const SizedBox(width: 9),
              Text(
                _t('مكان حفظ Arch Linux', 'Arch Linux storage'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'اختر الحفظ العام إذا أردت الاحتفاظ بملف RootFS بعد حذف التطبيق. ستعيد النسخة الجديدة اكتشافه والتحقق منه قبل التثبيت.',
              'Choose shared storage to retain RootFS after uninstall. The new installation detects and verifies it before use.',
            ),
            style: const TextStyle(color: Color(0xFFACBAC8), height: 1.4),
          ),
          const SizedBox(height: 14),
          _StorageOption(
            selected: !persistent,
            title: _t('تخزين داخلي خاص بالتطبيق', 'Private app storage'),
            detail: _t(
              'أكثر خصوصية، لكنه يُحذف عند حذف التطبيق.',
              'More private, but removed with the app.',
            ),
            icon: Icons.lock_outline,
            onTap: changing ? null : () => _select('internal'),
          ),
          const SizedBox(height: 9),
          _StorageOption(
            selected: persistent,
            title: _t('تخزين عام مستمر', 'Persistent shared storage'),
            detail: _t(
              'المجلد: /storage/emulated/0/ArchTerminal/rootfs — يبقى بعد حذف التطبيق.',
              'Folder survives app uninstall: /storage/emulated/0/ArchTerminal/rootfs.',
            ),
            icon: Icons.folder_copy_outlined,
            onTap: changing ? null : () => _select('persistent'),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0F15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF263442)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  persistent
                      ? _t(
                          'الحفظ العام ${ready ? 'جاهز' : 'يحتاج إذناً'}',
                          'Shared storage ${ready ? 'ready' : 'needs permission'}',
                        )
                      : _t('الحفظ الداخلي جاهز', 'Private storage ready'),
                  style: TextStyle(
                    color: ready
                        ? const Color(0xFF7EE787)
                        : const Color(0xFFFFB454),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                SelectableText(
                  path,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFFB7C5D3),
                  ),
                ),
                const SizedBox(height: 5),
                SelectableText(
                  command,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Color(0xFF62D5FF),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (persistent && !ready)
            FilledButton.icon(
              onPressed: changing ? null : _allowStorage,
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: Text(_t('تفعيل إذن التخزين', 'Enable storage permission')),
            ),
          TextButton.icon(
            onPressed: changing ? null : _copyCommand,
            icon: const Icon(Icons.content_copy_outlined),
            label: Text(_t('نسخ أمر الوصول', 'Copy access command')),
          ),
          OutlinedButton.icon(
            onPressed: changing ? null : _openLocation,
            icon: const Icon(Icons.folder_open_outlined),
            label: Text(
              _t(
                'فتح الموقع أو إظهار الإذن',
                'Open location or show permission',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _StorageOption extends StatelessWidget {
  const _StorageOption({
    required this.selected,
    required this.title,
    required this.detail,
    required this.icon,
    required this.onTap,
  });
  final bool selected;
  final String title, detail;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFF123047) : const Color(0xFF17212B),
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            Icon(
              icon,
              color: selected
                  ? const Color(0xFF62D5FF)
                  : const Color(0xFF94A5B7),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFACBAC8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected
                  ? const Color(0xFF62D5FF)
                  : const Color(0xFF708296),
            ),
          ],
        ),
      ),
    ),
  );
}
