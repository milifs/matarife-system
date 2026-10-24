// ============================================================
// PDF DEL CIERRE DE JORNADA DE UN COBRADOR (v19.2)
// ============================================================
// Lo que el cobrador cobró en el día: el total, cuánto de eso es efectivo
// que tiene que rendir, y el detalle cliente por cliente.
//
// Es un papel interno (Joaco y el cobrador), no va al cliente: por eso puede
// mostrar el desglose por medio de pago y el saldo que le queda a cada uno.
// El descuento del 6,2% de las transferencias NO aparece — el cierre es una
// rendición de plata cobrada, no un cálculo de ganancia.
//
// TRAMPAS DE dart_pdf QUE YA ESTÁN RESUELTAS ACÁ (mismas que en
// carga_pdf_service): las tarjetas van en pw.Inseparable para que no se parta
// un título de su contenido, y como una Inseparable más alta que la hoja hace
// explotar el armado, la lista de cobros se corta a mano en tandas. El
// pw.Divider de dart_pdf mide 16 de alto por defecto, no 1.
// ============================================================

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

class CierreJornadaService {
  static final _rojo = PdfColor.fromHex('#C62828');
  static final _verde = PdfColor.fromHex('#2E7D32');
  static final _marron = PdfColor.fromHex('#3B1508');

  /// Cuántos cobros entran en una tarjeta antes de abrir otra.
  static const _cobrosPorTarjeta = 20;

  static Future<pw.MemoryImage> _loadLogo() async {
    final bytes = await rootBundle.load('assets/logo.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  /// Genera el PDF del cierre y abre el diálogo de compartir/imprimir.
  static Future<void> generarYCompartir(ResumenJornada jornada) async {
    final logo = await _loadLogo();
    final pdf = generarPdf(jornada: jornada, logo: logo);

    final bytes = await pdf.save();
    final cobradorLimpio =
        jornada.cobrador.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final f = jornada.dia;
    final fechaArchivo = '${f.year}'
        '${f.month.toString().padLeft(2, '0')}'
        '${f.day.toString().padLeft(2, '0')}';

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'cierre_${cobradorLimpio}_$fechaArchivo.pdf',
    );
  }

  @visibleForTesting
  static pw.Document generarPdf({
    required ResumenJornada jornada,
    required pw.MemoryImage logo,
  }) {
    final pdf = pw.Document();

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
                  'Don Chacho - Generado el ${formatFechaHora(DateTime.now())}',
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
          _encabezado(jornada, logo),
          pw.SizedBox(height: 14),
          _bloqueResumen(jornada),
          pw.SizedBox(height: 10),
          ..._bloquesCobros(jornada),
        ],
      ),
    );

    return pdf;
  }

  static pw.Widget _encabezado(ResumenJornada jornada, pw.MemoryImage logo) {
    return pw.Row(
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
                  'Matarife - Cobranzas',
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
          padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#FBE9E7'),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'CIERRE DE JORNADA',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: _rojo,
                ),
              ),
              pw.Text(
                jornada.cobrador,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                formatFecha(jornada.dia),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _bloqueResumen(ResumenJornada jornada) {
    return _tarjeta(
      titulo: 'RESUMEN DEL DÍA',
      hijos: [
        _fila('Cobros registrados', jornada.cantidadPagos.toString()),
        _fila('Clientes', jornada.cantidadClientes.toString()),
        _separador(),
        _fila('Efectivo', formatPesos(jornada.efectivo)),
        _fila('Transferencia', formatPesos(jornada.transferencia)),
        _fila('Cheque', formatPesos(jornada.cheque)),
        if (!jornada.desgloseCompleto)
          _fila(
            'Sin medio cargado',
            formatPesos(jornada.sinDesglosar),
            valorGris: true,
          ),
        _separador(),
        _fila(
          'TOTAL COBRADO',
          formatPesos(jornada.total),
          destacado: true,
          color: _verde,
        ),
        pw.SizedBox(height: 6),
        _fila(
          'EFECTIVO A RENDIR',
          formatPesos(jornada.efectivo),
          destacado: true,
          color: _rojo,
        ),
      ],
    );
  }

  static List<pw.Widget> _bloquesCobros(ResumenJornada jornada) {
    final cobros = jornada.cobros;

    final pedazos = <List<CobroJornada>>[];
    for (var i = 0; i < cobros.length; i += _cobrosPorTarjeta) {
      pedazos.add(cobros.sublist(
        i,
        (i + _cobrosPorTarjeta).clamp(0, cobros.length),
      ));
    }
    if (pedazos.isEmpty) pedazos.add(const []);

    final tarjetas = <pw.Widget>[];
    for (var i = 0; i < pedazos.length; i++) {
      final esPrimera = i == 0;

      tarjetas.add(
        _tarjeta(
          titulo: esPrimera ? 'DETALLE DE COBROS' : 'DETALLE (continuación)',
          hijos: [
            if (pedazos[i].isEmpty)
              _fila('Sin cobros en el día', '', valorGris: true)
            else
              ...pedazos[i].map(_filaCobro),
          ],
        ),
      );
      if (i < pedazos.length - 1) tarjetas.add(pw.SizedBox(height: 10));
    }

    return tarjetas;
  }

  /// Un renglón por cobro: hora + cliente + medio a la izquierda, monto a la
  /// derecha. Todo en una línea para que una jornada larga entre en pocas hojas.
  static pw.Widget _filaCobro(CobroJornada cobro) {
    final detalle = [
      cobro.pago.numeroFormateado,
      if (cobro.mediosLabel.isNotEmpty) cobro.mediosLabel,
      if (cobro.cargadoOtroDia) 'cargado el ${formatFecha(cobro.pago.creadoEn)}',
    ].join(' · ');

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 34,
            child: pw.Text(
              cobro.hora,
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey600,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  cobro.clienteNombre,
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.Text(
                  detalle,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey500,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Text(
            formatPesos(cobro.monto),
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

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

  /// El Divider de dart_pdf reserva 16 de alto por defecto (no 1 como en
  /// Flutter), así que acá se fuerza compacto.
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
