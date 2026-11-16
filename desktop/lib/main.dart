import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    runApp(const CollegeBellApp());
  } catch (_) {
    runApp(const CollegeBellApp(
        home: Scaffold(
            body: Center(
      child: Text('College Bell could not start. Close the app and try again.'),
    ))));
  }
}

class CollegeBellApp extends StatelessWidget {
  final Widget home;
  const CollegeBellApp({super.key, this.home = const AuthGate()});

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: const Color(0xFF183456),
      surface: const Color(0xFFF4F6F9),
    ).copyWith(
      primary: const Color(0xFF183456),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE8EEF6),
      onPrimaryContainer: const Color(0xFF183456),
      secondaryContainer: const Color(0xFFE8EEF6),
      onSecondaryContainer: const Color(0xFF243B54),
      onSurface: const Color(0xFF182434),
      onSurfaceVariant: const Color(0xFF4D5B6D),
      outline: const Color(0xFF7B8797),
      outlineVariant: const Color(0xFFD6DEE8),
    );
    final rounded =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ARC College Bell',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        colorScheme: colors,
        scaffoldBackgroundColor: colors.surface,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF142B47),
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 64,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: colors.outlineVariant))),
        inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colors.outline))),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(
              color: colors.onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w700),
          contentTextStyle:
              TextStyle(color: colors.onSurfaceVariant, fontSize: 15),
          iconColor: colors.primary,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        dividerTheme: DividerThemeData(color: colors.outlineVariant),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.primary,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: rounded,
        ),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
                shape: rounded, minimumSize: const Size(48, 46))),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
                shape: rounded, minimumSize: const Size(48, 46))),
      ),
      home: home,
    );
  }
}
