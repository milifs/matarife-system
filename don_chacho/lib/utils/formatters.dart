// ============================================================
// UTILIDADES DE FORMATO - Moneda ARS y fechas
// ============================================================

import 'package:intl/intl.dart';

/// Formatea un número como moneda argentina: $1.234.567
String formatPesos(double monto) {
  final formatter = NumberFormat.currency(
    locale: 'es_AR',
    symbol: '\$',
    decimalDigits: 0,
  );
  return formatter.format(monto);
}

/// Formato corto - ahora usa el mismo formato completo sin decimales
String formatPesosCorto(double monto) {
  return formatPesos(monto);
}

/// Formatea kilogramos: 1.234 kg
String formatKg(double kg) {
  final formatter = NumberFormat('#,##0', 'es_AR');
  return '${formatter.format(kg)} kg';
}

/// Formatea fecha: 30/03/2026
String formatFecha(DateTime fecha) {
  return DateFormat('dd/MM/yyyy').format(fecha);
}

/// Formatea fecha corta: 30 mar
String formatFechaCorta(DateTime fecha) {
  return DateFormat('dd MMM', 'es').format(fecha);
}

/// Obtiene el lunes de la semana actual
DateTime lunesDeSemana(DateTime fecha) {
  return fecha.subtract(Duration(days: fecha.weekday - 1));
}

/// Rango de semana: "24 mar - 30 mar 2026"
String formatRangoSemana(DateTime fecha) {
  final lunes = lunesDeSemana(fecha);
  final domingo = lunes.add(const Duration(days: 6));
  final formatCorto = DateFormat('dd MMM', 'es');
  final formatLargo = DateFormat('dd MMM yyyy', 'es');
  return '${formatCorto.format(lunes)} - ${formatLargo.format(domingo)}';
}

/// Calcula días de vencimiento de un cliente
/// Retorna positivo si está vencido, negativo si aún tiene plazo
int diasVencimiento(DateTime fechaRemito, int plazoDias) {
  final vencimiento = fechaRemito.add(Duration(days: plazoDias));
  return DateTime.now().difference(vencimiento).inDays;
}
