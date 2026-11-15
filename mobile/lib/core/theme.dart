import 'package:flutter/material.dart';

abstract final class AdamTheme {
  static const orange = Color(0xFFFF7A20);
  static const background = Color(0xFF0B1014);
  static const surface = Color(0xFF172027);
  static const muted = Color(0xFF9DAAB3);
  static const border = Color(0xFF34414A);
  static TextStyle display(double size) => TextStyle(
    fontFamily: 'Oswald',
    fontSize: size,
    fontWeight: FontWeight.w700,
    fontStyle: FontStyle.italic,
    height: 1.1,
  );
  static ThemeData get theme => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: orange,
      onPrimary: background,
      secondary: orange,
      onSecondary: background,
      secondaryContainer: surface,
      onSecondaryContainer: Color(0xFFF5F6F7),
      surface: surface,
      onSurface: Color(0xFFF5F6F7),
    ),
    useMaterial3: true,
    textTheme: const TextTheme(
      bodyMedium: TextStyle(fontSize: 14, height: 1.4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        foregroundColor: background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        foregroundColor: Colors.white,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
  );
}

class Brand extends StatelessWidget {
  final double size;
  const Brand({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ADAM RUN', style: AdamTheme.display(size)),
        const SizedBox(width: 10),
        Text(
          '///',
          style: TextStyle(
            color: AdamTheme.orange,
            fontSize: size * .75,
            fontWeight: FontWeight.w900,
            letterSpacing: -3,
          ),
        ),
      ],
    ),
  );
}
