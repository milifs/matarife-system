// ============================================================
// SERVICIO DE REPARTO - PDF para el repartidor
// ============================================================
// Genera el PDF de UNA de las dos tablas de un día: la de CARNE
// (novillo) o la de CERDO, con su TOTAL MEDIAS, sus clientes y su
// SOBRANTE DEPÓSITO, más las notas sueltas del día.
//
// Son dos PDF separados a propósito: la carne y el cerdo los reparte
// gente distinta, y cada uno se lleva su hoja. Las notas del día van en
// los dos, porque son del reparto, no de la mercadería.
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
    required String tipo,
  }) async {
    final logo = await _loadLogo();
    final pdf =
        generarPdf(lista: lista, clientes: clientes, logo: logo, tipo: tipo);
    final bytes = await pdf.save();
    final semana = formatFecha(lista.semanaInicio).replaceAll('/', '-');
    await Printing.sharePdf(
      bytes: bytes,
      // El tipo va en el nombre: en el celular los dos PDF del mismo día
      // quedan uno al lado del otro y hay que poder distinguirlos.
      filename: 'reparto_${tipo}_${lista.dia}_$semana.pdf',
    );
  }

  /// Público para poder armar el documento en los tests sin pasar por
  /// Printing: los errores de layout de dart_pdf saltan recién acá.
  static pw.Document generarPdf({
    required RepartoLista lista,
    required List<Cliente> clientes,
    required pw.MemoryImage logo,
    required String tipo,
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

    // Las columnas que el usuario le agregó a mano a esta tabla.
    final extras = lista.columnasDe(tipo);

    pw.TableRow fila(String cliente, String sucursal, String medias,
            List<String> valores,
            {bool bold = false, PdfColor? bg}) =>
        pw.TableRow(
          decoration: bg != null ? pw.BoxDecoration(color: bg) : null,
          children: [
            celdaTexto(cliente, bold: bold),
            celdaTexto(sucursal),
            celdaNum(medias, bold: bold),
            for (var i = 0; i < extras.length; i++)
              celdaNum(i < valores.length ? valores[i] : '', bold: bold),
          ],
        );

    String txt(int v) => v == 0 ? '' : '$v';

    final titulo = tipo == tipoRepartoCerdo ? 'CERDO' : 'CARNE (NOVILLO)';

    // La tabla va como widgets sueltos y NO dentro de un Column: en un
    // MultiPage la Table se parte sola entre páginas, un Column no, y una
    // lista larga de clientes haría explotar el armado.
    List<pw.Widget> tabla() {
      final items = [...lista.itemsDe(tipo)]..sort((a, b) =>
          compararNombres(nombre(a.clienteId), nombre(b.clienteId)));
      return [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.4),
            1: const pw.FlexColumnWidth(1.8),
            2: const pw.FlexColumnWidth(0.9),
            for (var i = 0; i < extras.length; i++)
              3 + i: const pw.FlexColumnWidth(0.9),
          },
          children: [
            // Header de columnas
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: gris),
              children: [
                celdaTexto('CLIENTES', bold: true),
                celdaTexto('SUCURSAL', bold: true),
                celdaNum('MEDIAS', bold: true),
                for (final nombre in extras)
                  celdaNum(nombre.trim().toUpperCase(), bold: true),
              ],
            ),
            // TOTAL: las columnas extra no tienen un total cargado a mano,
            // se muestra la suma de lo repartido (y por eso no tienen
            // sobrante más abajo).
            fila(
              'TOTAL',
              '',
              txt(lista.totalDe(tipo)),
              [
                for (var i = 0; i < extras.length; i++)
                  txt(lista.repartidoExtra(tipo, i)),
              ],
              bold: true,
              bg: celeste,
            ),
            // Filas de clientes (orden alfabético por nombre)
            for (final it in items)
              fila(
                nombre(it.clienteId),
                it.sucursal,
                txt(it.medias),
                [
                  for (var i = 0; i < extras.length; i++)
                    txt(it.extraEn(i)),
                ],
              ),
            // SOBRANTE DEPOSITO
            fila(
              'SOBRANTE DEPOSITO',
              '',
              txt(lista.sobranteDe(tipo)),
              [for (var i = 0; i < extras.length; i++) '-'],
              bold: true,
              bg: celeste,
            ),
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
                  pw.Text('$titulo — Reparto del ${lista.diaLabel}',
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

          // La tabla de esta mercadería
          ...tabla(),
          pw.SizedBox(height: 18),

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
