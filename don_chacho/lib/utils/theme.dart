// ============================================================
// TEMA VISUAL - Granja Don Chacho
// ============================================================
// Paleta: rojo carne oscuro + blanco hueso + acentos cálidos
// Tipografía: Google Fonts (se configura en pubspec)
// ============================================================

import 'package:flutter/material.dart';

class AppTheme {
  // ── Colores principales ──
  static const Color primary = Color(0xFFC62828); // Rojo carne
  static const Color primaryDark = Color(0xFF8E0000);
  static const Color primaryLight = Color(0xFFFF5F52);

  static const Color surface = Color(0xFFFAF8F5); // Blanco hueso
  static const Color card = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF5F3F0);

  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B6B6B);
  static const Color textHint = Color(0xFF9E9E9E);

  static const Color success = Color(0xFF2E7D32);
  static const Color successBg = Color(0xFFE8F5E9);
  static const Color warning = Color(0xFFF57F17);
  static const Color warningBg = Color(0xFFFFF8E1);
  static const Color danger = Color(0xFFC62828);
  static const Color dangerBg = Color(0xFFFFEBEE);
  static const Color info = Color(0xFF1565C0);
  static const Color infoBg = Color(0xFFE3F2FD);

  static const Color border = Color(0xFFE0DDD8);
  static const Color divider = Color(0xFFF0EDE8);

  /// Línea de grilla de las pantallas tipo planilla (hoy la Lista de
  /// reparto). Más marcada que `border` a propósito: el usuario lee la
  /// tabla cruzando el nombre con el número y necesita ver el renglón.
  static const Color gridLine = Color(0xFFC9C3B9);

  /// Fondo del renglón que el mouse está señalando.
  static const Color gridHover = Color(0xFFFFF3E0);

  // ── Tema Material ──
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: background,
        colorScheme: const ColorScheme.light(
          primary: primary,
          onPrimary: Colors.white,
          secondary: primaryLight,
          surface: surface,
          error: danger,
        ),

        // AppBar
        appBarTheme: const AppBarTheme(
          backgroundColor: card,
          foregroundColor: textPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),

        // Cards
        cardTheme: const CardThemeData(
          color: card,
          elevation: 0,
          margin: EdgeInsets.zero,
        ),

        // Inputs
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: card,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: border, width: 0.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: border, width: 0.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: primary, width: 1.5),
          ),
          labelStyle: const TextStyle(color: textSecondary, fontSize: 14),
          hintStyle: const TextStyle(color: textHint, fontSize: 14),
        ),

        // Elevated Button
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        // Outlined Button
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: textPrimary,
            side: const BorderSide(color: border),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),

        // Bottom Navigation
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: card,
          selectedItemColor: primary,
          unselectedItemColor: textHint,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          selectedIconTheme: IconThemeData(size: 28),
          unselectedIconTheme: IconThemeData(size: 26),
        ),

        // Floating Action Button
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          elevation: 2,
        ),

        // Divider
        dividerTheme: const DividerThemeData(
          color: divider,
          thickness: 0.5,
          space: 0,
        ),
      );
}

// ── Widgets de estilo reutilizables ──

/// Pill/badge de estado con semáforo
class StatusPill extends StatelessWidget {
  final String text;
  final StatusType type;

  const StatusPill({
    super.key,
    required this.text,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (type) {
      case StatusType.success:
        bg = AppTheme.successBg;
        fg = AppTheme.success;
      case StatusType.warning:
        bg = AppTheme.warningBg;
        fg = AppTheme.warning;
      case StatusType.danger:
        bg = AppTheme.dangerBg;
        fg = AppTheme.danger;
      case StatusType.info:
        bg = AppTheme.infoBg;
        fg = AppTheme.info;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

enum StatusType { success, warning, danger, info }

/// Barra que explica por qué no se ve ningún saldo.
///
/// Va arriba de cualquier pantalla que muestre saldos cuando
/// `AppProvider.saldosConfiables` es false. Sin esto, la pantalla diría "no
/// disponible" en todas las filas y nadie sabría por qué: con el aviso, el
/// que lo ve sabe que es un permiso y no una falla, y a quién pedirlo.
class AvisoSaldosNoDisponibles extends StatelessWidget {
  /// Qué no se puede hacer por eso, si la pantalla quiere decirlo
  /// ("No se puede registrar un pago", "No se puede emitir el comprobante").
  final String? consecuencia;

  const AvisoSaldosNoDisponibles({super.key, this.consecuencia});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.warningBg,
        border: Border.all(color: AppTheme.warning.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 18, color: AppTheme.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Los saldos no están disponibles para tu usuario',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  consecuencia == null
                      ? 'Tu rol no tiene permiso para ver los pagos, así que el '
                          'saldo no se puede calcular. No es un error: pedile el '
                          'permiso al administrador.'
                      : '$consecuencia: tu rol no tiene permiso para ver los '
                          'pagos, así que el saldo no se puede calcular. Pedile '
                          'el permiso al administrador.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
