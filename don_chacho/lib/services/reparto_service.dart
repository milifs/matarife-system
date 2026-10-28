// ============================================================
// SERVICIO DE REPARTO - PDF para el repartidor
// ============================================================
// Genera un PDF con la lista de reparto de una semana/día: una tabla
// de CARNE (novillo) y otra de CERDO, cada una con su TOTAL MEDIAS,
// sus clientes y su SOBRANTE DEPÓSITO, más las notas sueltas.
// No involucra plata.
// ============================================================

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

class RepartoService {
  static Future<pw.MemoryImage> _loadLogo() async {
    final bytes = await rootBundle.load('assets/logo.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  static Future<void> generarYCompartir({
    required RepartoLista lista,
    required List<Cliente> clientes,
  }) async {
    final logo = await _loadLogo();
    final pdf = generarPdf(lista: lista, clientes: clientes, logo: logo);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'reparto_${lista.dia}_${formatFecha(lista.semanaInicio).replaceAll('/', '-')}.pdf',
    );
  }

  /// Público para poder armar el documento en los tests sin pasar por
  /// Printing: los errores de layout de dart_pdf saltan recién acá.
  static pw.Document generarPdf({
    required RepartoLista lista,
    required List<Cliente> clientes,
    required pw.MemoryImage logo,
  }) {
    final pdf = pw.Document();

    String nombre(String clienteId) {
      final c = clientes.where((c) => c.id == clienteId);
      return c.isEmpty ? '(cliente eliminado)' : c.first.nombreRazonSocial;
    }

    const rojo = PdfColor.fromInt(0xFFC62828);
    const gris = PdfColor.fromInt(0xFFEFEFEF);
    const celeste = PdfColor.fromInt(0xFFD6EAF8);

    pw.Widget celdaNum(String texto,
            {bool bold = false, PdfColor? bg}) =>
        pw.Container(
          alignment: pw.Alignment.center,
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          color: bg,
          child: pw.Text(
            texto,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );

    pw.Widget celdaTexto(String texto,
            {bool bold = false, PdfColor? bg}) =>
        pw.Container(
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          color: bg,
          child: pw.Text(
            texto,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );

    pw.TableRow fila(String cliente, String sucursal, int medias,
            {bool bold = false, PdfColor? bg}) =>
        pw.TableRow(
          decoration: bg != null ? pw.BoxDecoration(color: bg) : null,
          children: [
            celdaTexto(cliente, bold: bold),
            celdaTexto(sucursal),
            celdaNum(medias == 0 ? '' : '$medias', bold: bold),
          ],
        );

    // Una tabla por mercadería, cada una con su total y su sobrante.
    // Devuelve widgets sueltos y NO un Column: dentro de un MultiPage, la
    // Table se parte sola entre páginas, pero metida en un Column no, y una
    // lista larga de clientes haría explotar el armado.
    List<pw.Widget> tabla(String tipo) {
      final items = [...lista.itemsDe(tipo)]..sort((a, b) =>
          compararNombres(nombre(a.clienteId), nombre(b.clienteId)));
      return [
        pw.Text(
          tipo == tipoRepartoCerdo ? 'CERDO' : 'CARNE (NOVILLO)',
          style: pw.TextStyle(
              fontSize: 13, fontWeight: pw.FontWeight.bold, color: rojo),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.4),
            1: pw.FlexColumnWidth(1.8),
            2: pw.FlexColumnWidth(0.9),
          },
          children: [
            // Header de columnas
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: gris),
              children: [
                celdaTexto('CLIENTES', bold: true),
                celdaTexto('SUCURSAL', bold: true),
                celdaNum('MEDIAS', bold: true),
              ],
            ),
            // TOTAL MEDIAS
            fila('TOTAL MEDIAS', '', lista.totalDe(tipo),
                bold: true, bg: celeste),
            // Filas de clientes (orden alfabético por nombre)
            for (final it in items)
              fila(nombre(it.clienteId), it.sucursal, it.medias),
            // SOBRANTE DEPOSITO
            fila('SOBRANTE DEPOSITO', '', lista.sobranteDe(tipo),
                bold: true, bg: celeste),
          ],
        ),
      ];
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          // Encabezado
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(width: 46, height: 46, child: pw.Image(logo)),
              pw.SizedBox(width: 12),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('LISTA DE REPARTO',
                      style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: rojo)),
                  pw.Text('Reparto del ${lista.diaLabel}',
                      style: pw.TextStyle(
                          fontSize: 13, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Semana ${formatRangoSemana(lista.semanaInicio)}',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 16),

          // Las dos tablas
          for (final tipo in tiposReparto) ...[
            ...tabla(tipo),
            pw.SizedBox(height: 18),
          ],

          // Notas
          if (lista.notas.trim().isNotEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFFFF8E1),
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('NOTAS',
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700)),
                  pw.SizedBox(height: 4),
                  pw.Text(lista.notas.trim(),
                      style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );

    return pdf;
  }
}
