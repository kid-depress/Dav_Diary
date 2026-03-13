import 'package:diary/app/app_state.dart';
import 'package:diary/app/i18n.dart';
import 'package:diary/data/database/app_database.dart';
import 'package:diary/data/repositories/diary_repository.dart';
import 'package:diary/data/repositories/settings_repository.dart';
import 'package:diary/services/daily_quote_service.dart';
import 'package:diary/services/storage_service.dart';
import 'package:diary/services/sync_service.dart';
import 'package:diary/ui/home/home_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

class DiaryAppBootstrap extends StatefulWidget {
  const DiaryAppBootstrap({super.key});

  @override
  State<DiaryAppBootstrap> createState() => _DiaryAppBootstrapState();
}

class _DiaryAppBootstrapState extends State<DiaryAppBootstrap> {
  late final DiaryAppState _appState;
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    final diaryRepository = DiaryRepository(AppDatabase.instance);
    final settingsRepository = SettingsRepository();
    final syncService = SyncService(diaryRepository, settingsRepository);
    final storageService = const StorageService();
    final dailyQuoteService = const DailyQuoteService();
    _appState = DiaryAppState(
      diaryRepository: diaryRepository,
      settingsRepository: settingsRepository,
      syncService: syncService,
      storageService: storageService,
      dailyQuoteService: dailyQuoteService,
    );
    _initFuture = _appState.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        return ChangeNotifierProvider<DiaryAppState>.value(
          value: _appState,
          child: Consumer<DiaryAppState>(
            builder: (context, appState, _) {
              return MaterialApp(
                onGenerateTitle: (context) =>
                    tr(context, zh: '日记', en: 'Diary'),
                debugShowCheckedModeBanner: false,
                locale: appState.locale,
                supportedLocales: const [
                  Locale('zh', 'CN'),
                  Locale('en', 'US'),
                ],
                themeMode: appState.themeMode,
                theme: _buildTheme(
                  brightness: Brightness.light,
                  seedColor: appState.themeSeedColor,
                ),
                darkTheme: _buildTheme(
                  brightness: Brightness.dark,
                  seedColor: appState.themeSeedColor,
                ),
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  FlutterQuillLocalizations.delegate,
                ],
                home: const HomeShell(),
              );
            },
          ),
        );
      },
    );
  }

  ThemeData _buildTheme({
    required Brightness brightness,
    required Color seedColor,
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
      ),
    );
  }
}
