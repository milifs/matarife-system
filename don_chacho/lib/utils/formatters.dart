// ============================================================
// UTILIDADES DE FORMATO - Moneda ARS y fechas
// ============================================================

import 'package:flutter/services.dart';
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

/// Lo que se muestra en lugar de un saldo cuando no se puede saber cuánto es.
const String textoSaldoNoDisponible = 'no disponible';

/// Un saldo que **puede no estar disponible**.
///
/// Bajo RLS, un rol sin lectura sobre `pagos` no recibe un error: recibe la
/// tabla **vacía**. Y como `saldo = remitos − pagos ± notas`, eso no da un
/// saldo incompleto: da uno **más alto que el real**, que es el que hace que
/// alguien salga a cobrar plata que ya cobró. El provider corta antes
/// (`AppProvider.saldosConfiables`) y deja todos los saldos en 0; esto es
/// para que la pantalla no muestre ese 0 como si fuera un saldo.
///
/// Mismo criterio que `mediasSinPesar` en el depósito: un número que parece
/// exacto y no lo es es peor que no mostrarlo.
String formatPesosSaldo(double saldo, {required bool confiable}) =>
    confiable ? formatPesos(saldo) : textoSaldoNoDisponible;

/// Formatea kilogramos: 1.234 kg (muestra hasta 3 decimales solo si los hay)
String formatKg(double kg) {
  final formatter = NumberFormat('#,##0.###', 'es_AR');
  return '${formatter.format(kg)} kg';
}

/// Formatea una cantidad de medias reses: 10 / 10,5 / 3,33
///
/// Los cortes valen un tercio de media, así que el stock del depósito casi
/// siempre tiene decimales. Se muestran dos como máximo: la precisión fina
/// queda en el cálculo (que usa la fracción exacta) y acá importa que el
/// número se lea de un vistazo.
String formatMedias(double medias) {
  final formatter = NumberFormat('#,##0.##', 'es_AR');
  return formatter.format(medias);
}

/// Como [formatMedias] pero con la palabra: "1 media" / "8 medias"
String formatMediasConUnidad(double medias) {
  final texto = formatMedias(medias);
  return '$texto ${(medias - 1).abs() < 0.001 ? 'media' : 'medias'}';
}

/// Formatea un porcentaje: 58% / 55,49%
String formatPorcentaje(double valor) {
  final formatter = NumberFormat('#,##0.##', 'es_AR');
  return '${formatter.format(valor)}%';
}

// ============================================================
// ENTRADA DE NÚMEROS - separador de miles mientras se escribe
// ============================================================

/// Formatea un número para mostrarlo dentro de un TextField:
/// 10000000 -> "10.000.000" / 1234.5 -> "1.234,5"
/// Devuelve "" si el valor es 0 (para no arrancar los campos con un cero).
String textoMiles(double valor, {bool vacioSiCero = true}) {
  if (vacioSiCero && valor == 0) return '';
  final formatter = NumberFormat('#,##0.###', 'es_AR');
  return formatter.format(valor);
}

/// Convierte el texto de un campo con separador de miles a double.
/// Los puntos son miles y se descartan; la coma es el decimal.
/// "10.000.000" -> 10000000 / "1.234,5" -> 1234.5
double parseNumero(String texto, [double porDefecto = 0]) {
  final limpio = texto.replaceAll('.', '').replaceAll(',', '.').trim();
  if (limpio.isEmpty) return porDefecto;
  return double.tryParse(limpio) ?? porDefecto;
}

/// Agrega separadores de miles a medida que se escribe en un TextField.
///
/// Uso:
///   TextField(
///     keyboardType: TextInputType.number,
///     inputFormatters: [MilesInputFormatter()],
///   )
///
/// Para leer el valor usar [parseNumero]; para precargarlo, [textoMiles].
class MilesInputFormatter extends TextInputFormatter {
  /// Cantidad máxima de decimales permitidos después de la coma.
  final int decimales;

  const MilesInputFormatter({this.decimales = 3});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue anterior,
    TextEditingValue nuevo,
  ) {
    // Nos quedamos solo con dígitos y una única coma decimal.
    // Los puntos se descartan siempre: son los separadores de miles que
    // este mismo formatter insertó, no los tipeó la cajera.
    final buffer = StringBuffer();
    var yaHayComa = false;
    for (final char in nuevo.text.split('')) {
      if (char.compareTo('0') >= 0 && char.compareTo('9') <= 0) {
        buffer.write(char);
      } else if (char == ',' && !yaHayComa) {
        yaHayComa = true;
        buffer.write(',');
      }
    }
    final crudo = buffer.toString();

    if (crudo.isEmpty) {
      return const TextEditingValue(text: '');
    }

    // Cuántos caracteres significativos hay antes del cursor, para poder
    // reubicarlo después de insertar los puntos de miles.
    final hastaCursor = nuevo.text.substring(0, nuevo.selection.baseOffset.clamp(0, nuevo.text.length));
    var significativosAntes = 0;
    var comaVista = false;
    for (final char in hastaCursor.split('')) {
      if (char.compareTo('0') >= 0 && char.compareTo('9') <= 0) {
        significativosAntes++;
      } else if (char == ',' && !comaVista) {
        comaVista = true;
        significativosAntes++;
      }
    }

    // Separamos parte entera y decimal.
    final partes = crudo.split(',');
    var entera = partes[0];
    final tieneComa = partes.length > 1;
    var decimal = tieneComa ? partes[1] : '';
    if (decimal.length > decimales) {
      decimal = decimal.substring(0, decimales);
    }

    // Sacamos ceros a la izquierda ("007" -> "7") pero dejamos el "0" solo
    // para que se pueda escribir "0,5".
    entera = entera.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    final enteraFormateada = entera.isEmpty
        ? ''
        : NumberFormat('#,##0', 'es_AR').format(int.parse(entera));

    final texto = tieneComa
        ? '$enteraFormateada,$decimal'
        : enteraFormateada;

    // Reubicamos el cursor contando los mismos caracteres significativos.
    var offset = texto.length;
    var contados = 0;
    for (var i = 0; i < texto.length; i++) {
      final char = texto[i];
      if (char == '.') continue;
      contados++;
      if (contados == significativosAntes) {
        offset = i + 1;
        break;
      }
    }
    if (significativosAntes == 0) offset = 0;

    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(
        offset: offset.clamp(0, texto.length),
      ),
    );
  }
}

/// Formatea fecha: 30/03/2026
String formatFecha(DateTime fecha) {
  return DateFormat('dd/MM/yyyy').format(fecha);
}

/// Formatea fecha corta: 30 mar
String formatFechaCorta(DateTime fecha) {
  return DateFormat('dd MMM', 'es').format(fecha);
}

/// Formatea fecha con hora: 30/03/2026 14:32
String formatFechaHora(DateTime fecha) {
  return DateFormat('dd/MM/yyyy HH:mm').format(fecha);
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

/// Normaliza texto para búsquedas: minúsculas y sin acentos.
/// Así "José" y "jose" coinciden indistintamente.
String normalizarBusqueda(String texto) {
  const conAcento = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const sinAcento = 'aaaaaeeeeiiiiooooouuuunc';
  var resultado = texto.toLowerCase();
  for (var i = 0; i < conAcento.length; i++) {
    resultado = resultado.replaceAll(conAcento[i], sinAcento[i]);
  }
  return resultado;
}

/// Compara dos nombres para ordenar A→Z como los lee una persona:
/// sin distinguir mayúsculas ni acentos ("ángel" va con "Angel", no al final).
///
/// Es el criterio único de orden de los listados de clientes. Si empatan
/// normalizados, desempata con el texto crudo para que el orden sea estable.
int compararNombres(String a, String b) {
  final cmp = normalizarBusqueda(a).compareTo(normalizarBusqueda(b));
  return cmp != 0 ? cmp : a.compareTo(b);
}

/// Calcula días de vencimiento de un cliente
/// Retorna positivo si está vencido, negativo si aún tiene plazo
int diasVencimiento(DateTime fechaRemito, int plazoDias) {
  final vencimiento = fechaRemito.add(Duration(days: plazoDias));
  return DateTime.now().difference(vencimiento).inDays;
}
