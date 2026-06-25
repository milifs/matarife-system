// ============================================================
// SERVICIO DE RECIBOS - Genera PDF y comparte por WhatsApp
// ============================================================
// El PDF NO muestra descuentos ni neto recibido (info interna)
// Solo muestra: cliente, medios de pago, total, saldos
// ============================================================

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

class ReciboService {
  static Future<pw.MemoryImage> _loadLogo() async {
    final bytes = await rootBundle.load('assets/logo.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  /// Genera el PDF del recibo y abre el diálogo de compartir/imprimir
  static Future<void> generarYCompartirRecibo({
    required Pago pago,
    required List<PagoMedio> medios,
    required Cliente cliente,
    Vendedor? vendedor,
    required double saldoAnterior,
    required double saldoNuevo,
    List<Remito> remitosCliente = const [],
    List<Pago> pagosCliente = const [],
  }) async {
    final logo = await _loadLogo();
    final pdf = _generarPdf(
      pago: pago,
      medios: medios,
      cliente: cliente,
      vendedor: vendedor,
      saldoAnterior: saldoAnterior,
      saldoNuevo: saldoNuevo,
      remitosCliente: remitosCliente,
      pagosCliente: pagosCliente,
      logo: logo,
    );

    final bytes = await pdf.save();

    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'recibo_${cliente.nombreRazonSocial.replaceAll(' ', '_')}_${formatFecha(pago.fecha).replaceAll('/', '-')}.pdf',
    );
  }

  /// Abre WhatsApp con un mensaje predeterminado
  static Future<void> enviarPorWhatsApp({
    required String telefono,
    required String mensaje,
  }) async {
    final numeroLimpio = telefono.replaceAll(RegExp(r'[^\d+]'), '');
    final url =
        'https://wa.me/$numeroLimpio?text=${Uri.encodeComponent(mensaje)}';

    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  // ── Generación del PDF ──
  // NO incluye descuentos ni neto recibido (info interna)
  static pw.Document _generarPdf({
    required Pago pago,
    required List<PagoMedio> medios,
    required Cliente cliente,
    Vendedor? vendedor,
    required double saldoAnterior,
    required double saldoNuevo,
    List<Remito> remitosCliente = const [],
    List<Pago> pagosCliente = const [],
    required pw.MemoryImage logo,
  }) {
    // Calcular saldo vencido con FIFO
    final ahora = DateTime.now();
    final remitosOrdFifo = [...remitosCliente]
      ..sort((a, b) {
        final cmp = a.fecha.compareTo(b.fecha);
        return cmp != 0 ? cmp : a.numero.compareTo(b.numero);
      });
    // Incluir el pago actual para reflejar el saldo vencido post-pago
    double pagosRestantesFifo = pagosCliente.fold(0.0, (s, p) => s + p.montoTotal) + pago.montoTotal;
    double saldoVencido = 0;
    for (final r in remitosOrdFifo) {
      if (pagosRestantesFifo >= r.totalPesos) {
        pagosRestantesFifo -= r.totalPesos;
      } else {
        final deuda = r.totalPesos - pagosRestantesFifo;
        pagosRestantesFifo = 0;
        final vencimiento = r.fecha.add(Duration(days: cliente.plazoPagoDias));
        if (ahora.difference(vencimiento).inDays > 0) saldoVencido += deuda;
      }
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ── Encabezado ──
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      pw.Image(logo, width: 52, height: 52),
                      pw.SizedBox(width: 10),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('DON CHACHO',
                              style: pw.TextStyle(
                                fontSize: 22,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColor.fromHex('#3B1508'),
                              )),
                          pw.SizedBox(height: 4),
                          pw.Text('Matarife - Venta de medias reses',
                              style: const pw.TextStyle(
                                fontSize: 10,
                                color: PdfColors.grey600,
                              )),
                        ],
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#E8F5E9'),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('RECIBO DE PAGO',
                            style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#2E7D32'),
                            )),
                        pw.Text(
                          'N° ${pago.numeroFormateado}',
                          style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          'Fecha: ${formatFecha(pago.fecha)}',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              pw.SizedBox(height: 24),
              pw.Divider(color: PdfColors.grey300, thickness: 0.5),
              pw.SizedBox(height: 16),

              // ── Datos del cliente ──
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#FAFAFA'),
                  borderRadius: pw.BorderRadius.circular(8),
                  border:
                      pw.Border.all(color: PdfColors.grey300, width: 0.5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('CLIENTE',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey500,
                          letterSpacing: 1,
                        )),
                    pw.SizedBox(height: 6),
                    pw.Text(cliente.nombreRazonSocial,
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        )),
                    if (vendedor != null)
                      pw.Text('Vendedor: ${vendedor.nombreCompleto}',
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey600,
                          )),
                    if (cliente.telefono.isNotEmpty)
                      pw.Text('Tel: ${cliente.telefono}',
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey600,
                          )),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // ── Detalle de pago (sin descuentos) ──
              pw.Text('DETALLE DEL PAGO',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey500,
                    letterSpacing: 1,
                  )),
              pw.SizedBox(height: 10),

              pw.Table(
                border: pw.TableBorder.all(
                    color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#F5F5F5'),
                    ),
                    children: [
                      _tableCell('Medio de pago', header: true),
                      _tableCell('Monto', header: true),
                    ],
                  ),
                  ...medios.map((m) {
                    return pw.TableRow(
                      children: [
                        _tableCell(m.medioLabel),
                        _tableCell(formatPesos(m.monto)),
                      ],
                    );
                  }),
                ],
              ),

              pw.SizedBox(height: 16),

              // ── Total pagado ──
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#E8F5E9'),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL PAGADO',
                        style: pw.TextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        )),
                    pw.Text(formatPesos(pago.montoTotal),
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#2E7D32'),
                        )),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // ── Saldos ──
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(8),
                  border:
                      pw.Border.all(color: PdfColors.grey300, width: 0.5),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment:
                          pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Saldo anterior',
                            style: const pw.TextStyle(
                                fontSize: 11, color: PdfColors.grey600)),
                        pw.Text(formatPesos(saldoAnterior),
                            style: const pw.TextStyle(fontSize: 11)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment:
                          pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Pago realizado',
                            style: const pw.TextStyle(
                                fontSize: 11, color: PdfColors.grey600)),
                        pw.Text('-${formatPesos(pago.montoTotal)}',
                            style: pw.TextStyle(
                              fontSize: 11,
                              color: PdfColor.fromHex('#2E7D32'),
                            )),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Divider(color: PdfColors.grey300, thickness: 0.5),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisAlignment:
                          pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('SALDO RESTANTE',
                            style: pw.TextStyle(
                              fontSize: 12,
                              fontWeight: pw.FontWeight.bold,
                            )),
                        pw.Text(
                          formatPesos(saldoNuevo),
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: saldoNuevo > 0
                                ? PdfColor.fromHex('#C62828')
                                : PdfColor.fromHex('#2E7D32'),
                          ),
                        ),
                      ],
                    ),
                    if (saldoVencido > 0) ...[
                      pw.SizedBox(height: 6),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Saldo vencido',
                              style: const pw.TextStyle(
                                  fontSize: 11, color: PdfColors.grey600)),
                          pw.Text(
                            formatPesos(saldoVencido),
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#C62828'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // ── Detalle de deuda pendiente (siempre presente) ──
              _buildDetalleDeuda(
                cliente: cliente,
                remitosCliente: remitosCliente,
                pagosCliente: pagosCliente,
              ),

              pw.Spacer(),

              // ── Pie ──
              pw.Divider(color: PdfColors.grey300, thickness: 0.5),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text(
                  'Don Chacho - Recibo generado el ${formatFecha(DateTime.now())}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey400,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  static pw.Widget _tableCell(String text, {bool header = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: header ? 9 : 10,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: header ? PdfColors.grey600 : PdfColors.black,
        ),
      ),
    );
  }

  /// Sección de remitos pendientes + pagos aplicados (igual que Estado de Cuenta)
  static pw.Widget _buildDetalleDeuda({
    required Cliente cliente,
    required List<Remito> remitosCliente,
    required List<Pago> pagosCliente,
  }) {
    final ahora = DateTime.now();
    final totalPagos =
        pagosCliente.fold<double>(0, (s, p) => s + p.montoTotal);

    // FIFO: simular aplicación de pagos a remitos
    final remitosOrd = [...remitosCliente];
    remitosOrd.sort((a, b) {
      final cmp = a.fecha.compareTo(b.fecha);
      return cmp != 0 ? cmp : a.numero.compareTo(b.numero);
    });
    final pagosOrd = [...pagosCliente];
    pagosOrd.sort((a, b) => a.fecha.compareTo(b.fecha));

    // Trackear deuda restante por remito
    final remitoRestante = <String, double>{};
    for (final r in remitosOrd) {
      remitoRestante[r.id] = r.totalPesos;
    }

    // Trackear qué remitos cubre cada pago
    final pagoRemitosCubiertos = <String, Set<String>>{};
    for (final p in pagosOrd) {
      pagoRemitosCubiertos[p.id] = <String>{};
    }

    int idxRemito = 0;
    for (final p in pagosOrd) {
      double restantePago = p.montoTotal;
      while (restantePago > 0 && idxRemito < remitosOrd.length) {
        final r = remitosOrd[idxRemito];
        final deudaR = remitoRestante[r.id]!;
        if (deudaR <= 0) {
          idxRemito++;
          continue;
        }
        if (restantePago >= deudaR) {
          remitoRestante[r.id] = 0;
          pagoRemitosCubiertos[p.id]!.add(r.id);
          restantePago -= deudaR;
          idxRemito++;
        } else {
          remitoRestante[r.id] = deudaR - restantePago;
          pagoRemitosCubiertos[p.id]!.add(r.id);
          restantePago = 0;
        }
      }
    }

    // Remitos con deuda pendiente
    final remitosConDeuda = <Map<String, dynamic>>[];
    for (final r in remitosOrd) {
      final deuda = remitoRestante[r.id]!;
      if (deuda > 0) {
        final venc = r.fecha.add(Duration(days: cliente.plazoPagoDias));
        final diasV = ahora.difference(venc).inDays;
        remitosConDeuda.add({
          'remito': r,
          'deuda': deuda,
          'diasVencido': diasV,
          'vencido': diasV > 0,
        });
      }
    }

    // Pagos visibles (los que cubren al menos un remito pendiente)
    final remitosConDeudaIds =
        remitoRestante.entries
            .where((e) => e.value > 0)
            .map((e) => e.key)
            .toSet();
    final pagosVisibles = pagosOrd
        .where((p) => pagoRemitosCubiertos[p.id]!
            .any((rid) => remitosConDeudaIds.contains(rid)))
        .toList();
    final totalPagosVisibles =
        pagosVisibles.fold<double>(0, (s, p) => s + p.montoTotal);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Título
        pw.Text('DETALLE DE DEUDA PENDIENTE',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey500,
              letterSpacing: 1,
            )),
        pw.SizedBox(height: 8),

        // Tabla de remitos pendientes
        if (remitosConDeuda.isEmpty)
          pw.Text('Sin remitos pendientes',
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey400))
        else
          pw.Table(
            border:
                pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration:
                    pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
                children: [
                  _tableCell('Remito', header: true),
                  _tableCell('Fecha', header: true),
                  _tableCell('Estado', header: true),
                  _tableCell('Deuda', header: true),
                ],
              ),
              ...remitosConDeuda.map((d) {
                final r = d['remito'] as Remito;
                final deuda = d['deuda'] as double;
                final diasV = d['diasVencido'] as int;
                final vencido = d['vencido'] as bool;
                // diasV es positivo si está vencido, negativo si falta
                final diasFalta = diasV.abs();
                return pw.TableRow(
                  children: [
                    _tableCell(r.numeroFormateado),
                    _tableCell(formatFecha(r.fecha)),
                    pw.Container(
                      color: vencido ? PdfColor.fromHex('#FFF176') : null,
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: pw.Text(
                        vencido
                            ? 'Vencido $diasV d.'
                            : 'Por vencer $diasFalta d.',
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: vencido
                              ? pw.FontWeight.bold
                              : pw.FontWeight.normal,
                          color: vencido
                              ? PdfColor.fromHex('#B71C1C')
                              : PdfColors.black,
                        ),
                      ),
                    ),
                    pw.Container(
                      color: vencido ? PdfColor.fromHex('#FFF176') : null,
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: pw.Text(
                        formatPesos(deuda),
                        style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: vencido
                              ? pw.FontWeight.bold
                              : pw.FontWeight.normal,
                          color: vencido
                              ? PdfColor.fromHex('#B71C1C')
                              : PdfColors.black,
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),

        pw.SizedBox(height: 12),

        // Pagos aplicados
        if (pagosVisibles.isNotEmpty) ...[
          pw.Text('PAGOS APLICADOS',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey500,
                letterSpacing: 1,
              )),
          pw.SizedBox(height: 6),
          pw.Table(
            border:
                pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration:
                    pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
                children: [
                  _tableCell('Recibo', header: true),
                  _tableCell('Fecha', header: true),
                  _tableCell('Monto', header: true),
                  _tableCell('Aplicación', header: true),
                ],
              ),
              ...pagosVisibles.map((p) {
                final cubiertos = pagoRemitosCubiertos[p.id]!.length;
                final nota = cubiertos <= 1
                    ? 'Aplicado a 1 remito'
                    : 'Cubre $cubiertos remitos';
                return pw.TableRow(
                  children: [
                    _tableCell(p.numeroFormateado),
                    _tableCell(formatFecha(p.fecha)),
                    _tableCell(formatPesos(p.montoTotal)),
                    _tableCell(nota),
                  ],
                );
              }),
              pw.TableRow(
                decoration:
                    pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
                children: [
                  _tableCell(''),
                  _tableCell('TOTAL', header: true),
                  _tableCell(formatPesos(totalPagosVisibles),
                      header: true),
                  _tableCell(''),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }
}
