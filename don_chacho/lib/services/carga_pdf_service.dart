// ============================================================
// PDF DE UNA CARGA (compra de animales vivos a un proveedor)
// ============================================================
// Espejo de la pantalla de detalle: FAENA + PAGOS + DIFERENCIA DE RINDE.
//
// REGLA DEL BLOQUE DE RINDE: solo se imprime cuando el proveedor rindió
// de MENOS que el rinde asegurado (que es cuando hay algo para reclamar).
// Si rindió igual o de más, el bloque no va: el PDF es para discutir con
// el proveedor, no para mostrarle que le fue bien.
// ============================================================

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

class CargaPdfService {
  static final _rojo = PdfColor.fromHex('#C62828');
  static final _verde = PdfColor.fromHex('#2E7D32');
  static final _marron = PdfColor.fromHex('#3B1508');

  /// ¿Va el bloque de diferencia de rinde en el PDF?
  ///
  /// Solo cuando el proveedor rindió de MENOS que el rinde asegurado, que es
  /// cuando hay plata para reclamarle. Si rindió igual o de más, el bloque no
  /// se imprime. Mientras no se haya faenado tampoco hay rinde que mostrar.
  ///
  /// Ojo con el signo: `diferenciaRindeKg` es POSITIVO cuando rindió de menos
  /// (son los kilos que faltaron), así que la condición es `> 0`.
  static bool debeImprimirRinde(Carga carga) {
    final difKg = carga.diferenciaRindeKg;
    return carga.tieneFaena && difKg != null && difKg > 0;
  }

  static Future<pw.MemoryImage> _loadLogo() async {
    final bytes = await rootBundle.load('assets/logo.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  /// Genera el PDF de la carga y abre el diálogo de compartir/imprimir.
  static Future<void> generarYCompartir({
    required Carga carga,
    required String nombreProveedor,
    required List<CargaPago> pagos,
    required double saldoAnterior,
    required double pagado,
    required double saldoFinal,
  }) async {
    final logo = await _loadLogo();
    final pdf = generarPdf(
      carga: carga,
      nombreProveedor: nombreProveedor,
      pagos: pagos,
      saldoAnterior: saldoAnterior,
      pagado: pagado,
      saldoFinal: saldoFinal,
      logo: logo,
    );

    final bytes = await pdf.save();
    final proveedorLimpio =
        nombreProveedor.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');

    await Printing.sharePdf(
      bytes: bytes,
      filename: '${carga.numeroFormateado}_$proveedorLimpio.pdf',
    );
  }

  @visibleForTesting
  static pw.Document generarPdf({
    required Carga carga,
    required String nombreProveedor,
    required List<CargaPago> pagos,
    required double saldoAnterior,
    required double pagado,
    required double saldoFinal,
    required pw.MemoryImage logo,
  }) {
    final pdf = pw.Document();

    final imprimirRinde = debeImprimirRinde(carga);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        footer: (context) => pw.Column(
          children: [
            pw.Divider(height: 8, color: PdfColors.grey300, thickness: 0.5),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Don Chacho - Generado el ${formatFecha(DateTime.now())}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey400,
                  ),
                ),
                pw.Text(
                  'Página ${context.pageNumber} de ${context.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey400,
                  ),
                ),
              ],
            ),
          ],
        ),
        build: (context) => [
          _encabezado(carga, nombreProveedor, logo),
          pw.SizedBox(height: 14),
          _bloqueFaena(carga),
          pw.SizedBox(height: 10),
          ..._bloquePagos(
            carga: carga,
            pagos: pagos,
            saldoAnterior: saldoAnterior,
            pagado: pagado,
            saldoFinal: saldoFinal,
          ),
          if (imprimirRinde) ...[
            pw.SizedBox(height: 10),
            _bloqueRinde(carga),
          ],
          if (carga.observacion.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            _bloqueObservacion(carga.observacion),
          ],
        ],
      ),
    );

    return pdf;
  }

  // ── Encabezado: logo, número de carga y proveedor ──
  static pw.Widget _encabezado(
    Carga carga,
    String nombreProveedor,
    pw.MemoryImage logo,
  ) {
    return pw.Column(
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                pw.Image(logo, width: 44, height: 44),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'DON CHACHO',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: _marron,
                      ),
                    ),
                    pw.Text(
                      'Matarife - Compra de hacienda',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#FBE9E7'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'COMPRA A PROVEEDOR',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: _rojo,
                    ),
                  ),
                  pw.Text(
                    carga.numeroFormateado,
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    'Fecha: ${formatFecha(carga.fecha)}',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        _separador(),
        // El proveedor va como una linea del encabezado y no como tarjeta
        // aparte: es un solo dato y asi la carga tipica entra en una hoja.
        pw.Row(
          children: [
            _tituloBloque('PROVEEDOR'),
            pw.SizedBox(width: 10),
            pw.Text(
              nombreProveedor,
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  // ── FAENA ──
  static pw.Widget _bloqueFaena(Carga carga) {
    return _tarjeta(
      titulo: 'FAENA',
      hijos: [
        _fila('Animales', carga.cantidadAnimales.toString()),
        _fila('Kg vivo', formatKg(carga.kgVivo)),
        _fila('Desvaste', formatPorcentaje(carga.desvastePorcentaje)),
        _fila('Kg neto con desvaste', formatKg(carga.kgNeto)),
        _fila('Precio kg vivo', '${formatPesos(carga.precioKgVivo)}/kg'),
        _separador(),
        if (carga.tieneFaena) ...[
          _fila('Kg media res', formatKg(carga.kgMediaRes!)),
          _fila('Rinde de la carga', formatPorcentaje(carga.rindeCarga!)),
        ] else
          _fila('Kg media res', 'Falta faena', valorGris: true),
        _separador(),
        _fila(
          'TOTAL A PAGAR',
          formatPesos(carga.totalAPagar),
          destacado: true,
          color: _rojo,
        ),
      ],
    );
  }

  // ── PAGOS ──
  // Cuantos pagos entran en una tarjeta antes de abrir otra. Las tarjetas son
  // Inseparable (no se parten solas), asi que si una supera el alto de la hoja
  // dart_pdf tira excepcion en vez de maquetar. Por eso la lista se corta a
  // mano en pedazos que entran seguro.
  static const _pagosPorTarjeta = 18;

  static List<pw.Widget> _bloquePagos({
    required Carga carga,
    required List<CargaPago> pagos,
    required double saldoAnterior,
    required double pagado,
    required double saldoFinal,
  }) {
    final debe = saldoFinal < -0.5;

    // Pedazos de a _pagosPorTarjeta; si no hay pagos, igual va una tarjeta.
    final pedazos = <List<CargaPago>>[];
    for (var i = 0; i < pagos.length; i += _pagosPorTarjeta) {
      pedazos.add(pagos.sublist(
        i,
        (i + _pagosPorTarjeta).clamp(0, pagos.length),
      ));
    }
    if (pedazos.isEmpty) pedazos.add(const []);

    final tarjetas = <pw.Widget>[];
    for (var i = 0; i < pedazos.length; i++) {
      final esPrimera = i == 0;
      final esUltima = i == pedazos.length - 1;

      tarjetas.add(
        _tarjeta(
          titulo: esPrimera ? 'PAGOS' : 'PAGOS (continuación)',
          hijos: [
            if (esPrimera) ...[
              _fila('Saldo anterior', formatPesos(saldoAnterior)),
              pw.SizedBox(height: 6),
            ],
            if (pedazos[i].isEmpty)
              _fila('Sin pagos registrados', '', valorGris: true)
            else
              // Un renglon por pago (medio + fecha a la izquierda, monto a la
              // derecha). Van en una sola linea para que una carga con varios
              // pagos siga entrando en una hoja.
              ...pedazos[i].map(_filaPago),
            if (esUltima) ...[
              _separador(),
              _fila('Total pagado de esta carga', formatPesos(pagado)),
              _fila('Total a pagar', formatPesos(carga.totalAPagar)),
              pw.SizedBox(height: 6),
              _fila(
                debe ? 'SALDO (se le debe)' : 'SALDO A FAVOR',
                formatPesos(saldoFinal.abs()),
                destacado: true,
                color: debe ? _rojo : _verde,
              ),
            ],
          ],
        ),
      );
      if (!esUltima) tarjetas.add(pw.SizedBox(height: 10));
    }

    return tarjetas;
  }

  static pw.Widget _filaPago(CargaPago p) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: p.medioLabel,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.TextSpan(
                  text: '   ${formatFecha(p.fecha)}',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          ),
          pw.Text(
            formatPesos(p.monto),
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: _verde,
            ),
          ),
        ],
      ),
    );
  }

  // ── DIFERENCIA DE RINDE (solo cuando rindió de menos) ──
  static pw.Widget _bloqueRinde(Carga carga) {
    final difKg = carga.diferenciaRindeKg!;
    final difPesos = carga.diferenciaRindePesos!;

    return _tarjeta(
      titulo: 'DIFERENCIA DE RINDE',
      hijos: [
        _fila('Rinde asegurado', formatPorcentaje(carga.rindeAsegurado)),
        _fila('Kg esperados', formatKg(carga.kgEsperados)),
        _fila('Kg obtenidos', formatKg(carga.kgMediaRes!)),
        _separador(),
        _fila('Rindió de menos', formatKg(difKg),
            destacado: true, color: _rojo),
        _fila('Valorizado', formatPesos(difPesos),
            destacado: true, color: _rojo),
      ],
    );
  }

  // ── Observación ──
  static pw.Widget _bloqueObservacion(String texto) {
    return _tarjeta(
      titulo: 'OBSERVACIÓN',
      hijos: [
        pw.Text(texto, style: const pw.TextStyle(fontSize: 11)),
      ],
    );
  }

  // ── Helpers de layout ──

  /// Tarjeta con título y filas. Va envuelta en [pw.Inseparable] para que
  /// MultiPage no la parta al medio: sin eso el título "DIFERENCIA DE RINDE"
  /// quedaba solo al pie de una hoja y los números en la siguiente.
  static pw.Widget _tarjeta({
    required String titulo,
    required List<pw.Widget> hijos,
  }) {
    return pw.Inseparable(
        child: pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _tituloBloque(titulo),
          pw.SizedBox(height: 8),
          ...hijos,
        ],
      ),
    ));
  }

  /// Linea divisoria compacta. El Divider de dart_pdf reserva 16 de alto por
  /// defecto (no 1 como en Flutter), y con cuatro de esos la carga tipica se
  /// iba a una segunda hoja.
  static pw.Widget _separador() => pw.Divider(
        height: 10,
        color: PdfColors.grey300,
        thickness: 0.5,
      );

  static pw.Widget _tituloBloque(String texto) {
    return pw.Text(
      texto,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.grey500,
        letterSpacing: 1,
      ),
    );
  }

  static pw.Widget _fila(
    String etiqueta,
    String valor, {
    bool destacado = false,
    bool valorGris = false,
    PdfColor? color,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            etiqueta,
            style: pw.TextStyle(
              fontSize: destacado ? 12 : 11,
              fontWeight: destacado ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: destacado ? PdfColors.black : PdfColors.grey700,
            ),
          ),
          pw.Text(
            valor,
            style: pw.TextStyle(
              fontSize: destacado ? 12 : 11,
              fontWeight: destacado ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? (valorGris ? PdfColors.grey500 : PdfColors.black),
            ),
          ),
        ],
      ),
    );
  }
}
