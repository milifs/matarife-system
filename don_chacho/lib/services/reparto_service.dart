// ============================================================
// SERVICIO DE REPARTO - PDF para el repartidor
// ============================================================
// Genera un PDF con la lista de reparto de una semana/día:
// tabla de clientes × CARNE (novillo) / CERDO, con TOTAL MEDIAS,
// SOBRANTE DEPÓSITO y las notas sueltas. No involucra plata.
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
    final pdf = _generarPdf(lista: lista, clientes: clientes, logo: logo);
    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'reparto_${lista.dia}_${formatFecha(lista.semanaInicio).replaceAll('/', '-')}.pdf',
    );
  }

  static pw.Document _generarPdf({
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

    pw.TableRow fila(String cliente, int carne, int cerdo,
            {bool bold = false, PdfColor? bg}) =>
        pw.TableRow(
          decoration: bg != null ? pw.BoxDecoration(color: bg) : null,
          children: [
            celdaTexto(cliente, bold: bold),
            celdaNum(carne == 0 ? '' : '$carne', bold: bold),
            celdaNum(cerdo == 0 ? '' : '$cerdo', bold: bold),
          ],
        );

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

          // Tabla
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1),
            },
            children: [
              // Header de columnas
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: gris),
                children: [
                  celdaTexto('CLIENTES', bold: true),
                  celdaNum('CARNE', bold: true),
                  celdaNum('CERDO', bold: true),
                ],
              ),
              // TOTAL MEDIAS
              fila('TOTAL MEDIAS', lista.totalMediasCarne,
                  lista.totalMediasCerdo,
                  bold: true, bg: celeste),
              // Filas de clientes (respeta el orden cargado)
              for (final it in lista.items)
                fila(nombre(it.clienteId), it.mediasCarne, it.mediasCerdo),
              // SOBRANTE DEPOSITO
              fila('SOBRANTE DEPOSITO', lista.sobranteCarne,
                  lista.sobranteCerdo,
                  bold: true, bg: celeste),
            ],
          ),

          // Notas
          if (lista.notas.trim().isNotEmpty) ...[
            pw.SizedBox(height: 16),
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
        ],
      ),
    );

    return pdf;
  }
}
