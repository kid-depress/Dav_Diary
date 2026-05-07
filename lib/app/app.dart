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
import 'package:google_fonts/google_fonts.dart';
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
    const storageService = StorageService();
    const dailyQuoteService = DailyQuoteService();
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
    Color blend(Color from, Color to, double t) => Color.lerp(from, to, t)!;

    final baseScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    final isLight = brightness == Brightness.light;
    final scheme = baseScheme.copyWith(
      primary: blend(
        baseScheme.primary,
        baseScheme.primaryContainer,
        isLight ? 0.16 : 0.24,
      ),
      secondary: blend(
        baseScheme.secondary,
        baseScheme.secondaryContainer,
        isLight ? 0.12 : 0.2,
      ),
      onSurface: blend(
        baseScheme.onSurface,
        isLight ? Colors.black : Colors.white,
        isLight ? 0.04 : 0.06,
      ),
      onSurfaceVariant: blend(
        baseScheme.onSurfaceVariant,
        baseScheme.onSurface,
        0.08,
      ),
      surface: blend(
        baseScheme.surface,
        baseScheme.primary,
        isLight ? 0.03 : 0.07,
      ),
      surfaceContainerLowest: blend(
        baseScheme.surfaceContainerLowest,
        baseScheme.primary,
        isLight ? 0.015 : 0.06,
      ),
      surfaceContainerLow: blend(
        baseScheme.surfaceContainerLow,
        baseScheme.primary,
        isLight ? 0.025 : 0.08,
      ),
      surfaceContainerHighest: blend(
        baseScheme.surfaceContainerHighest,
        baseScheme.primary,
        isLight ? 0.045 : 0.11,
      ),
      tertiary: blend(
        baseScheme.tertiary,
        baseScheme.tertiaryContainer,
        isLight ? 0.1 : 0.16,
      ),
    );
    final textBase = ThemeData(brightness: brightness).textTheme;
    final bodyText = GoogleFonts.manropeTextTheme(
      textBase,
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
    final textTheme = bodyText.copyWith(
      headlineLarge: GoogleFonts.plusJakartaSans(
        textStyle: bodyText.headlineLarge,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: GoogleFonts.plusJakartaSans(
        textStyle: bodyText.headlineMedium,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: GoogleFonts.plusJakartaSans(
        textStyle: bodyText.headlineSmall,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: GoogleFonts.plusJakartaSans(
        textStyle: bodyText.titleLarge,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: GoogleFonts.plusJakartaSans(
        textStyle: bodyText.titleMedium,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: GoogleFonts.plusJakartaSans(
        textStyle: bodyText.titleSmall,
        fontWeight: FontWeight.w600,
      ),
      labelLarge: GoogleFonts.manrope(
        textStyle: bodyText.labelLarge,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: GoogleFonts.manrope(
        textStyle: bodyText.labelMedium,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: GoogleFonts.manrope(
        textStyle: bodyText.labelSmall,
        fontWeight: FontWeight.w600,
      ),
    );
    final radius = BorderRadius.circular(28);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: Colors.transparent,
      textTheme: textTheme,
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        backgroundColor: scheme.surface.withValues(alpha: isLight ? 0.84 : 0.7),
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer.withValues(alpha: 0.9),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
          textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 0.2,
          ),
        ),
        height: 58,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        tileColor: scheme.surfaceContainerLow,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        backgroundColor: scheme.surfaceContainerLow,
        selectedColor: scheme.secondaryContainer,
        side: BorderSide.none,
        labelStyle: TextStyle(color: scheme.onSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
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
          borderSide: BorderSide(
            color: scheme.primary.withValues(alpha: 0.72),
            width: 1.8,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
