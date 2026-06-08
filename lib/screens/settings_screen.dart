import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

class SettingsState {
  final ThemeMode themeMode;
  final int jpegQuality;
  final String exportFormat;

  /// One-time opt-in for online AI features. OFF by default so the app stays
  /// offline-by-default; on-device AI (e.g. cutout) runs regardless of this.
  /// Persisted so the user's privacy choice survives restarts.
  final bool aiOnlineEnabled;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.jpegQuality = 90,
    this.exportFormat = 'jpeg',
    this.aiOnlineEnabled = false,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    int? jpegQuality,
    String? exportFormat,
    bool? aiOnlineEnabled,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      jpegQuality: jpegQuality ?? this.jpegQuality,
      exportFormat: exportFormat ?? this.exportFormat,
      aiOnlineEnabled: aiOnlineEnabled ?? this.aiOnlineEnabled,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  static const _kAiOnline = 'ai_online_enabled';

  SettingsNotifier() : super(const SettingsState()) {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kAiOnline);
    if (enabled != null) {
      state = state.copyWith(aiOnlineEnabled: enabled);
    }
  }

  void setThemeMode(ThemeMode mode) => state = state.copyWith(themeMode: mode);
  void setJpegQuality(int q) => state = state.copyWith(jpegQuality: q);
  void setExportFormat(String f) => state = state.copyWith(exportFormat: f);

  Future<void> setAiOnlineEnabled(bool v) async {
    state = state.copyWith(aiOnlineEnabled: v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAiOnline, v);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
    (ref) => SettingsNotifier());

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader(label: 'Appearance'),
          _SettingTile(
            icon: Icons.dark_mode_outlined,
            title: 'Theme',
            subtitle: _themeName(settings.themeMode),
            onTap: () => _showThemePicker(context, notifier, settings.themeMode),
          ),
          _SectionHeader(label: 'Export'),
          _SettingTile(
            icon: Icons.image_outlined,
            title: 'Export format',
            subtitle: settings.exportFormat.toUpperCase(),
            onTap: () => _showFormatPicker(context, notifier, settings.exportFormat),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.high_quality_outlined, size: 22, color: Colors.grey),
                    const SizedBox(width: 16),
                    const Expanded(child: Text('JPEG Quality', style: TextStyle(fontSize: 15))),
                    Text('${settings.jpegQuality}%',
                        style: const TextStyle(fontSize: 13, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
                Slider(
                  value: settings.jpegQuality.toDouble(),
                  min: 50, max: 100, divisions: 10,
                  activeColor: AppTheme.primary,
                  onChanged: settings.exportFormat == 'jpeg'
                      ? (v) => notifier.setJpegQuality(v.round()) : null,
                ),
              ],
            ),
          ),
          const _InfoTile(
            icon: Icons.save_outlined,
            title: 'Originals are always kept',
            subtitle:
                'Edits are saved as a new copy in your gallery — the original is never modified',
            iconColor: Colors.green,
          ),
          _SectionHeader(label: 'AI features'),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome_outlined, color: Colors.grey),
            title: const Text('Enable online AI features', style: TextStyle(fontSize: 15)),
            subtitle: const Text(
              'Off by default. When on, AI features that need a server may send '
              'the photo you are editing to our AI service. On-device tools '
              '(like Cutout) always work offline regardless of this setting.',
              style: TextStyle(fontSize: 12),
            ),
            value: settings.aiOnlineEnabled,
            activeColor: AppTheme.primary,
            onChanged: (v) {
              if (v) {
                _confirmAiOptIn(context, notifier);
              } else {
                notifier.setAiOnlineEnabled(false);
              }
            },
          ),
          _SectionHeader(label: 'Privacy'),
          _InfoTile(
            icon: settings.aiOnlineEnabled ? Icons.wifi_outlined : Icons.wifi_off_outlined,
            title: settings.aiOnlineEnabled ? 'Online AI features enabled' : 'No internet access',
            subtitle: settings.aiOnlineEnabled
                ? 'Photos stay on-device except when you tap an online AI feature'
                : 'This app never connects to the internet',
            iconColor: settings.aiOnlineEnabled ? Colors.orange : Colors.green,
          ),
          _InfoTile(icon: Icons.person_off_outlined, title: 'No account required', subtitle: 'Open and edit instantly — no login ever', iconColor: Colors.green),
          _InfoTile(
            icon: settings.aiOnlineEnabled ? Icons.cloud_outlined : Icons.cloud_off_outlined,
            title: settings.aiOnlineEnabled ? 'Cloud only for online AI' : 'No cloud uploads',
            subtitle: settings.aiOnlineEnabled
                ? 'Photos are uploaded only when you use an online AI feature'
                : 'All your photos stay on your device only',
            iconColor: settings.aiOnlineEnabled ? Colors.orange : Colors.green,
          ),
          _InfoTile(icon: Icons.analytics_outlined, title: 'No tracking or analytics', subtitle: 'Zero data is collected or shared', iconColor: Colors.green),
          _SectionHeader(label: 'About'),
          _SettingTile(icon: Icons.info_outlined, title: 'Version', subtitle: '1.0.0 — Phase 1', onTap: null),
          _SettingTile(icon: Icons.gavel_outlined, title: 'Open source licences', onTap: () => showLicensePage(context: context)),
          _SettingTile(icon: Icons.star_outline_rounded, title: 'Rate on Play Store', subtitle: 'Enjoying PixelVault? Leave us a review!', onTap: () {}),
          const SizedBox(height: 32),
          const Center(
            child: Text('PixelVault — Free. Offline. Private. Forever.',
                style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _confirmAiOptIn(BuildContext context, SettingsNotifier notifier) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable online AI?'),
        content: const Text(
          'Online AI features (like AI upscale or generative fill) work by '
          'sending the photo you are editing to our AI service over the '
          'internet.\n\n'
          'Your photos are never uploaded for any other reason. On-device '
          'tools like Cutout keep working offline either way.\n\n'
          'You can turn this off any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              notifier.setAiOnlineEnabled(true);
              Navigator.pop(ctx);
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  String _themeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system: return 'Follow system';
      case ThemeMode.light: return 'Light';
      case ThemeMode.dark: return 'Dark';
    }
  }

  void _showThemePicker(BuildContext context, SettingsNotifier notifier, ThemeMode current) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Choose theme', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          ...ThemeMode.values.map((mode) => ListTile(
            leading: Icon(mode == ThemeMode.dark ? Icons.dark_mode : mode == ThemeMode.light ? Icons.light_mode : Icons.brightness_auto),
            title: Text(_themeName(mode)),
            trailing: mode == current ? const Icon(Icons.check, color: AppTheme.primary) : null,
            onTap: () { notifier.setThemeMode(mode); Navigator.pop(context); },
          )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showFormatPicker(BuildContext context, SettingsNotifier notifier, String current) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Export format', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
          ListTile(
            leading: const Icon(Icons.image_outlined), title: const Text('JPEG'),
            subtitle: const Text('Smaller file size, adjustable quality'),
            trailing: current == 'jpeg' ? const Icon(Icons.check, color: AppTheme.primary) : null,
            onTap: () { notifier.setExportFormat('jpeg'); Navigator.pop(context); },
          ),
          ListTile(
            leading: const Icon(Icons.image), title: const Text('PNG'),
            subtitle: const Text('Lossless quality, larger file size'),
            trailing: current == 'png' ? const Icon(Icons.check, color: AppTheme.primary) : null,
            onTap: () { notifier.setExportFormat('png'); Navigator.pop(context); },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(label.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary, letterSpacing: 0.8)),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  const _SettingTile({required this.icon, required this.title, this.subtitle, this.onTap});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey.shade600),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(fontSize: 12)) : null,
      trailing: onTap != null ? const Icon(Icons.chevron_right, color: Colors.grey) : null,
      onTap: onTap,
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconColor;
  const _InfoTile({required this.icon, required this.title, required this.subtitle, required this.iconColor});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: const TextStyle(fontSize: 15)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    );
  }
}
