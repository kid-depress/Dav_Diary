import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/models/webdav_config.dart';
import 'package:diary/ui/motion/motion_dialog.dart';
import 'package:diary/ui/motion/motion_route.dart';
import 'package:diary/ui/settings/trash_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted || ok) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context, zh: '无法打开链接', en: 'Cannot open link')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 118),
      children: [
        Text(
          tr(context, zh: '配置', en: 'Configuration'),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: colors.tertiary,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          tr(context, zh: '设置', en: 'Settings'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr(
            context,
            zh: '自定义外观、同步和隐私偏好。',
            en: 'Personalize appearance, sync and privacy preferences.',
          ),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 16),
        const _SettingsGroup(
          titleZh: '数据',
          titleEn: 'Data',
          children: [_ClearCacheTile(), _TrashTile(), _WebDavTile()],
        ),
        const SizedBox(height: 16),
        const _SettingsGroup(
          titleZh: '外观',
          titleEn: 'Appearance',
          children: [_AppearanceTile()],
        ),
        const SizedBox(height: 16),
        _SettingsGroup(
          titleZh: '关于',
          titleEn: 'About',
          children: [
            _SettingsActionTile(
              icon: Icons.info_outline,
              title: tr(context, zh: '项目主页', en: 'Project Page'),
              subtitle: tr(
                context,
                zh: '在 GitHub 上查看源代码',
                en: 'Open project repository on GitHub',
              ),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openLink(
                context,
                'https://github.com/kid-depress/Dav_Diary',
              ),
            ),
            _SettingsActionTile(
              icon: Icons.support_agent_outlined,
              title: tr(context, zh: '联系作者', en: 'Contact Author'),
              subtitle: tr(
                context,
                zh: '反馈建议与问题',
                en: 'Feedback and suggestions',
              ),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _openLink(
                context,
                'https://qun.qq.com/universal-share/share?ac=1&authKey=OwDtxNxyG47DX3WMUDnu91lAyFdkzIU613RHHxCVWrAs2iL15plLPUnpyj95SfjM&busi_data=eyJncm91cENvZGUiOiIxMDkxMTI1NDk1IiwidG9rZW4iOiJjMmM1d2FVMzNOd0NyaXVEeThGR2NjZFdNMVhZKzRpbzlhZ3krQS9lWWY2MzFnOUlGa1plRFErUHVwNW9NUUZ0IiwidWluIjoiMzQ2ODk0MzM2NyJ9&data=pg995AanOfOHor1w9a0u6DhsRI9j991Z3W8kmfoPzum9XTgpaJlgnyU8gCjJ2y-TP6KEkaKxRh1VkEECMt7Hug&svctype=4&tempid=h5_group_info',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.titleZh,
    required this.titleEn,
    required this.children,
  });

  final String titleZh;
  final String titleEn;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(context, zh: titleZh, en: titleEn),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i != children.length - 1) const SizedBox(height: 6),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsActionTile extends StatelessWidget {
  const _SettingsActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfaceContainerHighest,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: colors.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClearCacheTile extends StatelessWidget {
  const _ClearCacheTile();

  @override
  Widget build(BuildContext context) {
    return _SettingsActionTile(
      icon: Icons.cleaning_services_outlined,
      title: tr(context, zh: '清理附件缓存', en: 'Clear Attachment Cache'),
      subtitle: tr(
        context,
        zh: '移除已同步原图，按需重新下载。',
        en: 'Remove synced originals and re-download on demand.',
      ),
      onTap: () async {
        final confirmed = await showMotionDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(tr(context, zh: '清理缓存', en: 'Clear Cache')),
            content: Text(
              tr(
                context,
                zh: '将删除已同步的本地原图，缩略图会保留。是否继续？',
                en: 'Synced local originals will be removed. Continue?',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(tr(context, zh: '取消', en: 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(tr(context, zh: '清理', en: 'Clear')),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted) {
          return;
        }
        final removed = await context
            .read<DiaryAppState>()
            .clearSyncedAttachmentCache();
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                zh: '已清理 $removed 个缓存文件',
                en: 'Cleared $removed cached files',
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrashTile extends StatelessWidget {
  const _TrashTile();

  @override
  Widget build(BuildContext context) {
    return _SettingsActionTile(
      icon: Icons.delete_outline,
      title: tr(context, zh: '回收站', en: 'Trash'),
      subtitle: tr(
        context,
        zh: '恢复或永久删除日记。',
        en: 'Restore or permanently delete entries.',
      ),
      onTap: () {
        Navigator.of(context).push(buildPageTransitionRoute(const TrashPage()));
      },
    );
  }
}

class _WebDavTile extends StatelessWidget {
  const _WebDavTile();

  @override
  Widget build(BuildContext context) {
    return _SettingsActionTile(
      icon: Icons.cloud_outlined,
      title: tr(context, zh: 'WebDAV 同步', en: 'WebDAV Sync'),
      subtitle: tr(
        context,
        zh: '配置私有云同步参数。',
        en: 'Configure private cloud synchronization.',
      ),
      onTap: () {
        Navigator.of(
          context,
        ).push(buildPageTransitionRoute(const WebDavSettingsPage()));
      },
    );
  }
}

class _AppearanceTile extends StatelessWidget {
  const _AppearanceTile();

  @override
  Widget build(BuildContext context) {
    return _SettingsActionTile(
      icon: Icons.palette_outlined,
      title: tr(context, zh: '主题与语言', en: 'Theme & Language'),
      subtitle: tr(
        context,
        zh: '主题模式、配色种子与语言',
        en: 'Theme mode, seed color and language',
      ),
      onTap: () {
        Navigator.of(
          context,
        ).push(buildPageTransitionRoute(const AppearanceSettingsPage()));
      },
    );
  }
}

class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  static const _presetThemeSeedColors = [
    Color(0xFF34694A),
    Color(0xFF6B7A42),
    Color(0xFF586E8D),
    Color(0xFF9A6A45),
    Color(0xFF8A5C74),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, zh: '外观', en: 'Appearance')),
      ),
      body: Consumer<DiaryAppState>(
        builder: (context, appState, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, zh: '主题模式', en: 'Theme Mode'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text(tr(context, zh: '跟随系统', en: 'System')),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text(tr(context, zh: '浅色', en: 'Light')),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text(tr(context, zh: '深色', en: 'Dark')),
                          ),
                        ],
                        selected: {appState.themeMode},
                        onSelectionChanged: (selection) {
                          appState.setThemeMode(selection.first);
                        },
                      ),
                      const SizedBox(height: 18),
                      Text(
                        tr(context, zh: '主题种子色', en: 'Theme Seed Color'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: _presetThemeSeedColors.map((color) {
                          return _ThemeSeedColorOption(
                            color: color,
                            selected:
                                appState.themeSeedColor.toARGB32() ==
                                color.toARGB32(),
                            onTap: () => appState.setThemeSeedColor(color),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '#${appState.themeSeedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(context, zh: '语言', en: 'Language'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'zh_CN', label: Text('简体中文')),
                          ButtonSegment(value: 'en_US', label: Text('English')),
                        ],
                        selected: {
                          appState.locale.languageCode == 'en'
                              ? 'en_US'
                              : 'zh_CN',
                        },
                        onSelectionChanged: (selection) {
                          final code = selection.first;
                          appState.setLocale(
                            code == 'en_US'
                                ? const Locale('en', 'US')
                                : const Locale('zh', 'CN'),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr(context, zh: '每日一句', en: 'Daily Quote')),
                        subtitle: Text(
                          tr(
                            context,
                            zh: '每天请求一次短句并显示在首页顶部。',
                            en: 'Fetch one quote per day for the home header.',
                          ),
                        ),
                        value: appState.dailyQuoteEnabled,
                        onChanged: appState.setDailyQuoteEnabled,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeSeedColorOption extends StatelessWidget {
  const _ThemeSeedColorOption({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outlineVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 2.4 : 1.2),
        ),
        child: selected
            ? Icon(
                Icons.check,
                size: 18,
                color:
                    ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              )
            : null,
      ),
    );
  }
}

class WebDavSettingsPage extends StatefulWidget {
  const WebDavSettingsPage({super.key});

  @override
  State<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends State<WebDavSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _remoteDirController = TextEditingController();

  bool _loaded = false;
  bool _obscurePassword = true;
  ConflictStrategy _conflictStrategy = ConflictStrategy.lastWriteWins;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) {
      return;
    }
    final appState = context.read<DiaryAppState>();
    final config = appState.webDavConfig;
    _urlController.text = config.serverUrl;
    _userController.text = config.username;
    _passwordController.text = config.password;
    _remoteDirController.text = config.remoteDir;
    _conflictStrategy = config.conflictStrategy;
    _loaded = true;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _remoteDirController.dispose();
    super.dispose();
  }

  Future<bool> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return false;
    }
    final appState = context.read<DiaryAppState>();
    final config = WebDavConfig(
      serverUrl: _urlController.text.trim(),
      username: _userController.text.trim(),
      password: _passwordController.text.trim(),
      remoteDir: _remoteDirController.text.trim().isEmpty
          ? '/diary'
          : _remoteDirController.text.trim(),
      conflictStrategy: _conflictStrategy,
    );
    await appState.updateWebDavConfig(config);
    if (!mounted) {
      return false;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(context, zh: '已保存', en: 'Saved')),
      ),
    );
    return true;
  }

  Future<void> _saveAndTest(DiaryAppState appState) async {
    final okToContinue = await _saveConfig();
    if (!okToContinue || !mounted) {
      return;
    }
    try {
      final ok = await appState.testWebDavConnection();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? tr(context, zh: '连接成功', en: 'Connected')
                : tr(context, zh: '连接失败', en: 'Failed to connect'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr(context, zh: '连接失败：', en: 'Connection failed: ')}$e',
          ),
        ),
      );
    }
  }

  Future<void> _syncNow(DiaryAppState appState) async {
    final okToContinue = await _saveConfig();
    if (!okToContinue || !mounted) {
      return;
    }
    final result = await appState.syncNow();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${result.message} ${tr(context, zh: '上传', en: 'up')}:${result.uploaded} ${tr(context, zh: '下载', en: 'down')}:${result.downloaded} ${tr(context, zh: '冲突', en: 'conflicts')}:${result.conflicts}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, zh: 'WebDAV', en: 'WebDAV')),
      ),
      body: Consumer<DiaryAppState>(
        builder: (context, appState, _) {
          final colors = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 146),
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    color: colors.primaryContainer,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.cloud_done_outlined,
                    color: colors.onPrimaryContainer,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tr(context, zh: '同步你的日记', en: 'Sync Your Diary'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tr(
                  context,
                  zh: '连接你的私有 WebDAV 空间用于备份与多端同步。',
                  en: 'Connect private WebDAV storage for backup and sync.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            labelText: tr(
                              context,
                              zh: '服务器地址',
                              en: 'Server URL',
                            ),
                            hintText: 'https://dav.example.com',
                            prefixIcon: const Icon(Icons.dns_outlined),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? tr(context, zh: '必填项', en: 'Required')
                              : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _userController,
                          decoration: InputDecoration(
                            labelText: tr(context, zh: '用户名', en: 'Username'),
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? tr(context, zh: '必填项', en: 'Required')
                              : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: tr(context, zh: '密码', en: 'Password'),
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(
                                  () => _obscurePassword = !_obscurePassword,
                                );
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                            ),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? tr(context, zh: '必填项', en: 'Required')
                              : null,
                        ),
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: _remoteDirController,
                          decoration: InputDecoration(
                            labelText: tr(
                              context,
                              zh: '远程目录',
                              en: 'Remote Dir',
                            ),
                            prefixIcon: const Icon(Icons.folder_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<ConflictStrategy>(
                          initialValue: _conflictStrategy,
                          decoration: InputDecoration(
                            labelText: tr(
                              context,
                              zh: '冲突策略',
                              en: 'Conflict Strategy',
                            ),
                            prefixIcon: const Icon(Icons.rule_outlined),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: ConflictStrategy.lastWriteWins,
                              child: Text(
                                tr(
                                  context,
                                  zh: '最后写入优先',
                                  en: 'Last Write Wins',
                                ),
                              ),
                            ),
                            DropdownMenuItem(
                              value: ConflictStrategy.keepBoth,
                              child: Text(
                                tr(context, zh: '保留双方', en: 'Keep Both'),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _conflictStrategy = value);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (appState.lastSyncAt != null)
                Text(
                  '${tr(context, zh: '上次同步：', en: 'Last sync: ')}${DateFormat('yyyy-MM-dd HH:mm').format(appState.lastSyncAt!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.tertiaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: colors.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(
                          context,
                          zh: '账号密码仅保存在本机。',
                          en: 'Credentials are only stored on this device.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onTertiaryContainer,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Consumer<DiaryAppState>(
        builder: (context, appState, _) {
          return SafeArea(
            minimum: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: appState.syncing
                      ? null
                      : () => _saveAndTest(appState),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                  ),
                  icon: const Icon(Icons.network_check_outlined),
                  label: Text(
                    tr(context, zh: '保存并测试连接', en: 'Save & Test Connection'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: appState.syncing ? null : () => _syncNow(appState),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                  icon: appState.syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(
                    appState.syncing
                        ? tr(context, zh: '同步中...', en: 'Syncing...')
                        : tr(context, zh: '立即同步', en: 'Sync now'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
