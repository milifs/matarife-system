// ============================================================
// SERVICIO ESTADO DE CUENTA - PDF por cliente
// ============================================================
// Genera un PDF con el detalle completo de la cuenta del cliente:
// - Datos del cliente
// - Detalle de ventas (remitos) con fechas y montos
// - Detalle de pagos recibidos
// - Saldos vencidos y por vencer
// ============================================================

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';
import '../utils/formatters.dart';

class EstadoCuentaService {
  static Future<pw.MemoryImage> _loadLogo() async {
    final bytes = await rootBundle.load('assets/logo.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  static Future<void> generarYCompartir({
    required Cliente cliente,
    Vendedor? vendedor,
    required List<Remito> remitos,
    required List<Pago> pagos,
    required double saldoTotal,
  }) async {
    final logo = await _loadLogo();
    final pdf = _generarPdf(
      cliente: cliente,
      vendedor: vendedor,
      remitos: remitos,
      pagos: pagos,
      saldoTotal: saldoTotal,
      logo: logo,
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'estado_cuenta_${cliente.nombreRazonSocial.replaceAll(' ', '_')}_${formatFecha(DateTime.now()).replaceAll('/', '-')}.pdf',
    );
  }

  static pw.Document _generarPdf({
    required Cliente cliente,
    Vendedor? vendedor,
    required List<Remito> remitos,
    required List<Pago> pagos,
    required double saldoTotal,
    required pw.MemoryImage logo,
  }) {
    final pdf = pw.Document();
    final ahora = DateTime.now();

    // Ordenar remitos y pagos por fecha (FIFO)
    final remitosOrdenados = [...remitos];
    remitosOrdenados.sort((a, b) {
      final cmp = a.fecha.compareTo(b.fecha);
      return cmp != 0 ? cmp : a.numero.compareTo(b.numero);
    });
    final pagosOrdenados = [...pagos];
    pagosOrdenados.sort((a, b) => a.fecha.compareTo(b.fecha));

    // Simulación FIFO: aplicamos pagos sobre remitos en orden
    // Para cada remito trackeamos cuánto se pagó
    // Para cada pago trackeamos a qué remitos se aplicó
    final remitoRestante = <String, double>{};
    for (final r in remitosOrdenados) {
      remitoRestante[r.id] = r.totalPesos;
    }

    final pagoRemitosCubiertos = <String, Set<String>>{};
    final pagoTieneRemitoPendiente = <String, bool>{};
    for (final p in pagosOrdenados) {
      pagoRemitosCubiertos[p.id] = <String>{};
      pagoTieneRemitoPendiente[p.id] = false;
    }

    int idxRemito = 0;
    for (final p in pagosOrdenados) {
      double restantePago = p.montoTotal;
      while (restantePago > 0 && idxRemito < remitosOrdenados.length) {
        final r = remitosOrdenados[idxRemito];
        final deudaRemito = remitoRestante[r.id]!;
        if (deudaRemito <= 0) {
          idxRemito++;
          continue;
        }
        if (restantePago >= deudaRemito) {
          // Cubre este remito completamente
          remitoRestante[r.id] = 0;
          pagoRemitosCubiertos[p.id]!.add(r.id);
          restantePago -= deudaRemito;
          idxRemito++;
        } else {
          // Cubre parcialmente este remito
          remitoRestante[r.id] = deudaRemito - restantePago;
          pagoRemitosCubiertos[p.id]!.add(r.id);
          restantePago = 0;
        }
      }
    }

    // Determinar qué remitos tienen deuda pendiente (los que quedaron con restante > 0)
    final remitosConDeudaIds = <String>{};
    for (final entry in remitoRestante.entries) {
      if (entry.value > 0) remitosConDeudaIds.add(entry.key);
    }

    // Un pago es "visible" si cubrió (total o parcialmente) al menos un remito
    // que actualmente tiene deuda pendiente
    for (final p in pagosOrdenados) {
      final cubiertos = pagoRemitosCubiertos[p.id]!;
      pagoTieneRemitoPendiente[p.id] =
          cubiertos.any((rid) => remitosConDeudaIds.contains(rid));
    }

    // Armar detalleDeuda para la tabla de remitos pendientes
    final detalleDeuda = <Map<String, dynamic>>[];
    for (final r in remitosOrdenados) {
      final deuda = remitoRestante[r.id]!;
      if (deuda > 0) {
        final vencimiento =
            r.fecha.add(Duration(days: cliente.plazoPagoDias));
        final diasVencido = ahora.difference(vencimiento).inDays;
        detalleDeuda.add({
          'remito': r,
          'deuda': deuda,
          'vencimiento': vencimiento,
          'diasVencido': diasVencido,
          'vencido': diasVencido > 0,
        });
      }
    }

    final saldoVencido = detalleDeuda
        .where((d) => d['vencido'] == true)
        .fold<double>(0, (sum, d) => sum + (d['deuda'] as double));
    final saldoPorVencer = detalleDeuda
        .where((d) => d['vencido'] == false)
        .fold<double>(0, (sum, d) => sum + (d['deuda'] as double));

    // Pagos visibles = los que cubren al menos un remito pendiente
    final pagosVisibles = pagosOrdenados
        .where((p) => pagoTieneRemitoPendiente[p.id] == true)
        .toList();
    final totalPagosVisibles =
        pagosVisibles.fold<double>(0, (sum, p) => sum + p.montoTotal);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => _buildHeader(cliente, vendedor, logo),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          pw.SizedBox(height: 16),

          // ── Resumen de cuenta ──
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F5F5F5'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _summaryItem(
                    'Pagado a cuenta', formatPesos(totalPagosVisibles),
                    color: PdfColor.fromHex('#2E7D32')),
                _summaryItem('Saldo total', formatPesos(saldoTotal),
                    color: saldoTotal > 0
                        ? PdfColor.fromHex('#C62828')
                        : PdfColor.fromHex('#2E7D32')),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          // ── Remitos pendientes de pago ──
          pw.Text('REMITOS PENDIENTES DE PAGO',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey500,
                letterSpacing: 1,
              )),
          pw.SizedBox(height: 8),

          if (detalleDeuda.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              child: pw.Text('No hay remitos pendientes de pago',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey400)),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1),
                1: const pw.FlexColumnWidth(1.2),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FlexColumnWidth(1.3),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#F5F5F5')),
                  children: [
                    _cell('N° Remito', header: true),
                    _cell('Fecha', header: true),
                    _cell('Vencimiento', header: true),
                    _cell('Estado', header: true),
                    _cell('Deuda', header: true),
                  ],
                ),
                ...detalleDeuda.map((d) {
                  final r = d['remito'] as Remito;
                  final venc = d['vencimiento'] as DateTime;
                  final vencido = d['vencido'] as bool;
                  final dias = d['diasVencido'] as int;
                  final deuda = d['deuda'] as double;
                  return pw.TableRow(
                    decoration: vencido
                        ? pw.BoxDecoration(
                            color: PdfColor.fromHex('#FFF176'))
                        : null,
                    children: [
                      _cell(r.numeroFormateado),
                      _cell(formatFecha(r.fecha)),
                      _cell(formatFecha(venc)),
                      _cell(vencido
                          ? 'Vencido $dias d.'
                          : 'Por vencer ${-dias} d.'),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 5),
                        child: pw.Text(
                          formatPesos(deuda),
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: vencido
                                ? PdfColor.fromHex('#C62828')
                                : PdfColor.fromHex('#F57F17'),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#F5F5F5')),
                  children: [
                    _cell(''),
                    _cell(''),
                    _cell(''),
                    _cell('TOTAL PENDIENTE', header: true),
                    _cell(
                        formatPesos(saldoVencido + saldoPorVencer),
                        header: true),
                  ],
                ),
              ],
            ),

          pw.SizedBox(height: 20),

          // ── Pagos aplicados a la deuda pendiente ──
          pw.Text('PAGOS APLICADOS A DEUDA PENDIENTE',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey500,
                letterSpacing: 1,
              )),
          pw.SizedBox(height: 8),

          if (pagosVisibles.isEmpty)
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              child: pw.Text(
                  'No hay pagos aplicados a la deuda pendiente',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey400)),
            )
          else
            pw.Table(
              border: pw.TableBorder.all(
                  color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.0),
                1: const pw.FlexColumnWidth(1.2),
                2: const pw.FlexColumnWidth(1.2),
                3: const pw.FlexColumnWidth(1.8),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#F5F5F5')),
                  children: [
                    _cell('N° Recibo', header: true),
                    _cell('Fecha', header: true),
                    _cell('Monto', header: true),
                    _cell('Aplicación', header: true),
                  ],
                ),
                ...pagosVisibles.map((p) {
                  final cubiertos = pagoRemitosCubiertos[p.id]!.length;
                  String nota;
                  if (cubiertos == 0) {
                    nota = '-';
                  } else if (cubiertos == 1) {
                    nota = 'Aplicado a 1 remito';
                  } else {
                    nota = 'Cubre $cubiertos remitos';
                  }
                  return pw.TableRow(
                    children: [
                      _cell(p.numeroFormateado),
                      _cell(formatFecha(p.fecha)),
                      _cell(formatPesos(p.montoTotal)),
                      _cell(nota),
                    ],
                  );
                }),
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#F5F5F5')),
                  children: [
                    _cell(''),
                    _cell('TOTAL', header: true),
                    _cell(formatPesos(totalPagosVisibles), header: true),
                    _cell(''),
                  ],
                ),
              ],
            ),

          pw.SizedBox(height: 20),

          // ── Saldos pendientes movido a la primera tabla ──


          pw.SizedBox(height: 24),

          // ── Saldo final ──
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: saldoTotal > 0
                  ? PdfColor.fromHex('#FFEBEE')
                  : PdfColor.fromHex('#E8F5E9'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('SALDO TOTAL',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    )),
                pw.Text(
                  formatPesos(saldoTotal),
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: saldoTotal > 0
                        ? PdfColor.fromHex('#C62828')
                        : PdfColor.fromHex('#2E7D32'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf;
  }

  static pw.Widget _buildHeader(Cliente cliente, Vendedor? vendedor, pw.MemoryImage logo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              children: [
                pw.Image(logo, width: 50, height: 50),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('DON CHACHO',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#3B1508'),
                        )),
                    pw.Text('Matarife - Venta de medias reses',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#E3F2FD'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('ESTADO DE CUENTA',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#1565C0'),
                      )),
                  pw.Text('Fecha: ${formatFecha(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
        pw.SizedBox(height: 12),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#FAFAFA'),
            borderRadius: pw.BorderRadius.circular(8),
            border:
                pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('CLIENTE',
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey500,
                          letterSpacing: 1,
                        )),
                    pw.SizedBox(height: 4),
                    pw.Text(cliente.nombreRazonSocial,
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                        )),
                    if (vendedor != null)
                      pw.Text(
                          'Vendedor: ${vendedor.nombreCompleto}',
                          style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.grey600)),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  if (cliente.telefono.isNotEmpty)
                    pw.Text('Tel: ${cliente.telefono}',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey600)),
                  pw.Text(
                      'Plazo de pago: ${cliente.plazoPagoDias} dias',
                      style: const pw.TextStyle(
                          fontSize: 9, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Don Chacho - Estado de cuenta generado el ${formatFecha(DateTime.now())}',
              style:
                  const pw.TextStyle(fontSize: 7, color: PdfColors.grey400),
            ),
            pw.Text(
              'Pagina ${context.pageNumber} de ${context.pagesCount}',
              style:
                  const pw.TextStyle(fontSize: 7, color: PdfColors.grey400),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _summaryItem(String label, String value,
      {PdfColor? color}) {
    return pw.Column(
      children: [
        pw.Text(label,
            style: const pw.TextStyle(
                fontSize: 9, color: PdfColors.grey500)),
        pw.SizedBox(height: 4),
        pw.Text(value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: color,
            )),
      ],
    );
  }

  static pw.Widget _cell(String text, {bool header = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: header ? 9 : 10,
          fontWeight:
              header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: header ? PdfColors.grey600 : PdfColors.black,
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  // REPORTE PDF DEL VENDEDOR (consolidado)
  // ═══════════════════════════════════════════

  static Future<void> generarReporteVendedor({
    required Vendedor vendedor,
    required List<Cliente> clientes,
    required List<Remito> remitos,
    required List<Pago> pagos,
  }) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();
    final ahora = DateTime.now();

    // Para cada cliente, calcular estado de cuenta
    final clientesData = <Map<String, dynamic>>[];

    for (final cliente in clientes) {
      final remitosCliente =
          remitos.where((r) => r.clienteId == cliente.id).toList();
      final pagosCliente =
          pagos.where((p) => p.clienteId == cliente.id).toList();

      final totalRemitos =
          remitosCliente.fold<double>(0, (s, r) => s + r.totalPesos);
      final totalPagos =
          pagosCliente.fold<double>(0, (s, p) => s + p.montoTotal);
      final saldo = totalRemitos - totalPagos;

      if (saldo <= 0) continue;

      // FIFO para deuda por remito
      final remitosOrd = [...remitosCliente];
      remitosOrd.sort((a, b) {
        final cmp = a.fecha.compareTo(b.fecha);
        return cmp != 0 ? cmp : a.numero.compareTo(b.numero);
      });
      final detalleDeuda = <Map<String, dynamic>>[];
      double pagosApl = totalPagos;
      for (final r in remitosOrd) {
        if (pagosApl >= r.totalPesos) {
          pagosApl -= r.totalPesos;
        } else {
          final deuda = r.totalPesos - pagosApl;
          pagosApl = 0;
          final venc =
              r.fecha.add(Duration(days: cliente.plazoPagoDias));
          final diasV = ahora.difference(venc).inDays;
          detalleDeuda.add({
            'remito': r,
            'deuda': deuda,
            'vencimiento': venc,
            'diasVencido': diasV,
            'vencido': diasV > 0,
          });
        }
      }

      clientesData.add({
        'cliente': cliente,
        'saldo': saldo,
        'detalleDeuda': detalleDeuda,
        'totalRemitos': totalRemitos,
        'totalPagos': totalPagos,
      });
    }

    // Ordenar por saldo descendente
    clientesData.sort(
        (a, b) => (b['saldo'] as double).compareTo(a['saldo'] as double));

    final saldoTotalVendedor =
        clientesData.fold<double>(0, (s, d) => s + (d['saldo'] as double));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    pw.Image(logo, width: 46, height: 46),
                    pw.SizedBox(width: 10),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('DON CHACHO',
                            style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#3B1508'),
                            )),
                        pw.Text('Matarife - Venta de medias reses',
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey500)),
                      ],
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                        color: PdfColor.fromHex('#C62828'), width: 1.5),
                    borderRadius: pw.BorderRadius.circular(6),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text('REPORTE VENDEDOR',
                          style: pw.TextStyle(
                            fontSize: 10,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#C62828'),
                          )),
                      pw.Text('Fecha: ${formatFecha(ahora)}',
                          style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F5F5F5'),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('VENDEDOR',
                          style: const pw.TextStyle(
                              fontSize: 8, color: PdfColors.grey500)),
                      pw.Text(vendedor.nombreCompleto,
                          style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                          '${clientes.length} clientes · Tel: ${vendedor.telefono}',
                          style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Saldo total',
                          style: const pw.TextStyle(
                              fontSize: 8, color: PdfColors.grey500)),
                      pw.Text(formatPesos(saldoTotalVendedor),
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: saldoTotalVendedor > 0
                                ? PdfColor.fromHex('#C62828')
                                : PdfColor.fromHex('#2E7D32'),
                          )),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
          ],
        ),
        footer: (context) => pw.Column(
          children: [
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Reporte generado el ${formatFecha(ahora)}',
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey400),
                ),
                pw.Text(
                  'Pagina ${context.pageNumber} de ${context.pagesCount}',
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey400),
                ),
              ],
            ),
          ],
        ),
        build: (context) {
          final widgets = <pw.Widget>[];

          for (final data in clientesData) {
            final cliente = data['cliente'] as Cliente;
            final saldo = data['saldo'] as double;
            final detalleDeuda =
                data['detalleDeuda'] as List<Map<String, dynamic>>;

            widgets.add(pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 14),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(
                    color: PdfColors.grey300, width: 0.5),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Nombre cliente + saldo
                  pw.Row(
                    mainAxisAlignment:
                        pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment:
                            pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(cliente.nombreRazonSocial,
                              style: pw.TextStyle(
                                  fontSize: 12,
                                  fontWeight: pw.FontWeight.bold)),
                          pw.Text(
                              'Tel: ${cliente.telefono} · Plazo: ${cliente.plazoPagoDias} días',
                              style: const pw.TextStyle(
                                  fontSize: 8,
                                  color: PdfColors.grey500)),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment:
                            pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text('Saldo',
                              style: const pw.TextStyle(
                                  fontSize: 8,
                                  color: PdfColors.grey500)),
                          pw.Text(formatPesos(saldo),
                              style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold,
                                color: saldo > 0
                                    ? PdfColor.fromHex('#C62828')
                                    : PdfColor.fromHex('#2E7D32'),
                              )),
                        ],
                      ),
                    ],
                  ),

                  // Tabla de remitos pendientes
                  if (detalleDeuda.isNotEmpty) ...[
                    pw.SizedBox(height: 8),
                    pw.Table(
                      border: pw.TableBorder.all(
                          color: PdfColors.grey300, width: 0.5),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(1),
                        1: const pw.FlexColumnWidth(1),
                        2: const pw.FlexColumnWidth(1.2),
                        3: const pw.FlexColumnWidth(1),
                      },
                      children: [
                        pw.TableRow(
                          decoration: pw.BoxDecoration(
                              color: PdfColor.fromHex('#F5F5F5')),
                          children: [
                            _cell('Remito', header: true),
                            _cell('Fecha', header: true),
                            _cell('Estado', header: true),
                            _cell('Deuda', header: true),
                          ],
                        ),
                        ...detalleDeuda.map((d) {
                          final r = d['remito'] as Remito;
                          final deuda = d['deuda'] as double;
                          final diasV = d['diasVencido'] as int;
                          final vencido = d['vencido'] as bool;
                          final diasFalta = diasV.abs();
                          return pw.TableRow(
                            children: [
                              _cell(r.numeroFormateado),
                              _cell(formatFecha(r.fecha)),
                              pw.Container(
                                color: vencido
                                    ? PdfColor.fromHex('#FFF176')
                                    : null,
                                padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
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
                                color: vencido
                                    ? PdfColor.fromHex('#FFF176')
                                    : null,
                                padding: const pw.EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 5),
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
                  ] else ...[
                    pw.SizedBox(height: 6),
                    pw.Text('Sin remitos pendientes',
                        style: const pw.TextStyle(
                            fontSize: 8,
                            color: PdfColors.grey400)),
                  ],
                ],
              ),
            ));
          }

          return widgets;
        },
      ),
    );

    final bytes = await pdf.save();
    final nombre =
        'reporte_${vendedor.nombreCompleto.replaceAll(' ', '_')}_${formatFecha(ahora).replaceAll('/', '-')}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: nombre);
  }

  // ═══════════════════════════════════════════
  // PDF NOTA DE PEDIDO
  // ═══════════════════════════════════════════

  static Future<void> generarPdfNotaPedido({
    required NotaPedido ndp,
    required String clienteNombre,
    String? remitoNumero, // si ya fue confirmada
  }) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();
    final ahora = DateTime.now();

    final totalKg = ndp.items.fold<double>(0, (s, i) => i.totalKg + s);
    final totalPesos =
        ndp.items.fold<double>(0, (s, i) => s + i.totalKg * i.precioPorMedia);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (_) => _buildNdpHeader(ndp, clienteNombre, remitoNumero, logo),
        footer: (ctx) => pw.Column(
          children: [
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Don Chacho - ${ndp.numeroFormateado} - ${formatFecha(ahora)}',
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey400),
                ),
                pw.Text(
                  'Pagina ${ctx.pageNumber} de ${ctx.pagesCount}',
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey400),
                ),
              ],
            ),
          ],
        ),
        build: (_) => [
          pw.SizedBox(height: 16),

          // ── Tabla de items ──
          pw.Text('DETALLE',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey500,
                letterSpacing: 1,
              )),
          pw.SizedBox(height: 8),

          pw.Table(
            border:
                pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(2.5),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(1.3),
            },
            children: [
              pw.TableRow(
                decoration:
                    pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
                children: [
                  _cell('Descripción', header: true),
                  _cell('Medias', header: true),
                  _cell('Kg por media', header: true),
                  _cell('Total kg', header: true),
                  _cell('Precio por kg.', header: true),
                  _cell('Subtotal', header: true),
                ],
              ),
              ...ndp.items.map((item) {
                final kgStr = item.kgsPorMedia
                    .map((kg) => formatKg(kg))
                    .join(' / ');
                return pw.TableRow(
                  children: [
                    _cell(item.descripcion.isNotEmpty
                        ? item.descripcion
                        : '-'),
                    _cell(item.cantidadMedias.toString()),
                    _cell(kgStr),
                    _cell(formatKg(item.totalKg)),
                    _cell(formatPesos(item.precioPorMedia)),
                    _cell(formatPesos(item.totalPesos)),
                  ],
                );
              }),
            ],
          ),

          pw.SizedBox(height: 20),

          // ── Totales ──
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(14),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F5F5F5'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text('Total kg:  ',
                          style: const pw.TextStyle(
                              fontSize: 11, color: PdfColors.grey600)),
                      pw.Text(formatKg(totalKg),
                          style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                  pw.SizedBox(height: 6),
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.Text('Total nota:  ',
                          style: const pw.TextStyle(
                              fontSize: 13, color: PdfColors.grey600)),
                      pw.Text(formatPesos(totalPesos),
                          style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#C62828'),
                          )),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final nombre =
        '${ndp.numeroFormateado}_${clienteNombre.replaceAll(' ', '_')}_${formatFecha(ndp.fecha).replaceAll('/', '-')}.pdf';
    await Printing.sharePdf(bytes: bytes, filename: nombre);
  }

  static pw.Widget _buildNdpHeader(
      NotaPedido ndp, String clienteNombre, String? remitoNumero, pw.MemoryImage logo) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Row(
              children: [
                pw.Image(logo, width: 50, height: 50),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('DON CHACHO',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#3B1508'),
                        )),
                    pw.Text('Matarife - Venta de medias reses',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#E8F5E9'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('NOTA DE PEDIDO',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#2E7D32'),
                      )),
                  pw.Text(ndp.numeroFormateado,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                      )),
                  pw.Text('Fecha: ${formatFecha(ndp.fecha)}',
                      style: const pw.TextStyle(fontSize: 9)),
                  if (remitoNumero != null)
                    pw.Text('Remito: $remitoNumero',
                        style: pw.TextStyle(
                            fontSize: 9,
                            color: PdfColor.fromHex('#1565C0'))),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
        pw.SizedBox(height: 10),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#FAFAFA'),
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('CLIENTE',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey500,
                        letterSpacing: 1,
                      )),
                  pw.SizedBox(height: 4),
                  pw.Text(clienteNombre,
                      style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.Text(
                ndp.esConfirmado
                    ? 'CONFIRMADA'
                    : ndp.esRechazado
                        ? 'RECHAZADA'
                        : 'PENDIENTE',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: ndp.esConfirmado
                      ? PdfColor.fromHex('#2E7D32')
                      : ndp.esRechazado
                          ? PdfColor.fromHex('#C62828')
                          : PdfColor.fromHex('#E65100'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  // PDF COMISIÓN DE VENDEDOR
  // ═══════════════════════════════════════════

  static Future<void> generarPdfComision({
    required Vendedor vendedor,
    required DateTime desde,
    required DateTime hasta,
    required List<Remito> remitos,
    required Map<String, Cliente> clientesMap,
    required double kgNovillo,
    required double kgCerdo,
    required double totalVentas,
    required double porcentaje,
    required double comision,
  }) async {
    final logo = await _loadLogo();
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        footer: (ctx) => pw.Column(
          children: [
            pw.Divider(color: PdfColors.grey300, thickness: 0.5),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Don Chacho - Liquidación de comisión generada el ${formatFecha(DateTime.now())}',
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey400),
                ),
                pw.Text(
                  'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                  style: const pw.TextStyle(
                      fontSize: 7, color: PdfColors.grey400),
                ),
              ],
            ),
          ],
        ),
        build: (ctx) => [
          // ── Encabezado ──
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Image(logo, width: 40, height: 40),
                  pw.SizedBox(width: 10),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('DON CHACHO',
                          style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#3B1508'),
                          )),
                      pw.Text('Liquidación de comisión',
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
              pw.Text(formatFecha(DateTime.now()),
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey600)),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Divider(
              color: PdfColor.fromHex('#C62828'), thickness: 1.5),
          pw.SizedBox(height: 12),

          // ── Vendedor y período ──
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FAFAFA'),
              border: pw.Border.all(
                  color: PdfColors.grey300, width: 0.5),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('VENDEDOR',
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey500,
                            letterSpacing: 1)),
                    pw.SizedBox(height: 3),
                    pw.Text(vendedor.nombreCompleto,
                        style: pw.TextStyle(
                            fontSize: 13,
                            fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('PERÍODO',
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey500,
                            letterSpacing: 1)),
                    pw.SizedBox(height: 3),
                    pw.Text(
                        '${formatFecha(desde)} al ${formatFecha(hasta)}',
                        style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // ── Resumen de ventas ──
          pw.Text('RESUMEN DE VENTAS',
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey500,
                  letterSpacing: 1)),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F5F5F5'),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _comisionStatPdf('Remitos', '${remitos.length}'),
                _comisionStatPdf('Kg Novillo', formatKg(kgNovillo)),
                _comisionStatPdf('Kg Cerdo', formatKg(kgCerdo)),
                _comisionStatPdf('Total ventas',
                    formatPesos(totalVentas),
                    bold: true),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // ── Detalle de remitos ──
          pw.Text('DETALLE DE REMITOS',
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey500,
                  letterSpacing: 1)),
          pw.SizedBox(height: 8),
          pw.Table(
            border:
                pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(2.5),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(
                decoration:
                    pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
                children: [
                  _cell('N° Remito', header: true),
                  _cell('Fecha', header: true),
                  _cell('Cliente', header: true),
                  _cell('Kg', header: true),
                  _cell('Total', header: true),
                ],
              ),
              ...remitos.map((r) {
                final cliente = clientesMap[r.clienteId];
                return pw.TableRow(
                  children: [
                    _cell(r.numeroFormateado),
                    _cell(formatFecha(r.fecha)),
                    _cell(cliente?.nombreRazonSocial ?? '-'),
                    _cell(formatKg(r.totalKg)),
                    _cell(formatPesos(r.totalPesos)),
                  ],
                );
              }),
              pw.TableRow(
                decoration:
                    pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
                children: [
                  _cell(''),
                  _cell(''),
                  _cell('TOTAL', header: true),
                  _cell(formatKg(kgNovillo + kgCerdo), header: true),
                  _cell(formatPesos(totalVentas), header: true),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 28),

          // ── Liquidación ──
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FFF8F8'),
              border: pw.Border.all(
                  color: PdfColor.fromHex('#C62828'), width: 1),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text('LIQUIDACIÓN DE COMISIÓN',
                      style: pw.TextStyle(
                          fontSize: 11,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#C62828'),
                          letterSpacing: 1)),
                ),
                pw.SizedBox(height: 12),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total ventas del período:',
                        style: const pw.TextStyle(fontSize: 11)),
                    pw.Text(formatPesos(totalVentas),
                        style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Porcentaje de comisión:',
                        style: const pw.TextStyle(fontSize: 11)),
                    pw.Text(
                        '${porcentaje % 1 == 0 ? porcentaje.toInt() : porcentaje.toStringAsFixed(2)}%',
                        style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Divider(
                    color: PdfColor.fromHex('#C62828'), thickness: 0.8),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('COMISIÓN A PAGAR:',
                        style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#C62828'))),
                    pw.Text(formatPesos(comision),
                        style: pw.TextStyle(
                            fontSize: 16,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#C62828'))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'comision_${vendedor.nombreCompleto.replaceAll(' ', '_')}_${formatFecha(DateTime.now()).replaceAll('/', '-')}.pdf',
    );
  }

  static pw.Widget _comisionStatPdf(String label, String value,
      {bool bold = false}) {
    return pw.Column(
      children: [
        pw.Text(label,
            style: const pw.TextStyle(
                fontSize: 9, color: PdfColors.grey500)),
        pw.SizedBox(height: 3),
        pw.Text(value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight:
                  bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            )),
      ],
    );
  }
}
