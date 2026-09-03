// ============================================================
// DETALLE DE CLIENTE - Remitos con deuda pendiente
// ============================================================
// Solo muestra remitos que aún no están 100% saldados.
// Los saldados se ven en Consultas > Remitos saldados.
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';
import '../services/estado_cuenta_service.dart';
import 'pago_form_screen.dart';
import 'remito_form_screen.dart';
import 'consultas_screen.dart' show abrirWhatsApp;

class ClienteDetalleScreen extends StatefulWidget {
  final Cliente cliente;

  const ClienteDetalleScreen({super.key, required this.cliente});

  @override
  State<ClienteDetalleScreen> createState() => _ClienteDetalleScreenState();
}

class _ClienteDetalleScreenState extends State<ClienteDetalleScreen> {
  late Cliente _cliente;

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
  }

  Future<void> _cambiarVendedor(BuildContext context, AppProvider app) async {
    String? vendedorSeleccionado = _cliente.vendedorId;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Cambiar vendedor'),
          content: DropdownButtonFormField<String>(
            value: vendedorSeleccionado,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Vendedor'),
            items: app.vendedores
                .map((v) => DropdownMenuItem(
                      value: v.id,
                      child: Text(v.nombreCompleto),
                    ))
                .toList(),
            onChanged: (val) => setDialogState(() => vendedorSeleccionado = val),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (vendedorSeleccionado == null ||
                    vendedorSeleccionado == _cliente.vendedorId) {
                  Navigator.pop(ctx);
                  return;
                }
                _cliente.vendedorId = vendedorSeleccionado!;
                final nav = Navigator.of(ctx);
                await app.editarCliente(_cliente);
                if (mounted) {
                  setState(() {});
                  nav.pop();
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_cliente.nombreRazonSocial),
        actions: [
          Consumer<AppProvider>(
            builder: (context, app, _) {
              if (!app.tienePermiso('gestionar_clientes')) {
                return const SizedBox.shrink();
              }
              return IconButton(
                icon: const Icon(Icons.person_search_outlined),
                tooltip: 'Cambiar vendedor',
                onPressed: () => _cambiarVendedor(context, app),
              );
            },
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, app, _) {
          final vendedor = app.vendedorPorId(_cliente.vendedorId);
          final saldo = app.getSaldoCliente(_cliente.id);

          // Obtener remitos del cliente (solo confirmados, igual que _recalcularSaldos)
          final remitosCliente = app.remitos
              .where((r) => r.clienteId == _cliente.id && r.esConfirmado)
              .toList();

          // Obtener pagos del cliente
          final pagosCliente = app.pagos
              .where((p) => p.clienteId == _cliente.id)
              .toList();

          // Notas de crédito / débito del cliente (para mostrarlas en la lista).
          final notasCliente = app.notasCreditoDebito
              .where((n) => n.clienteId == _cliente.id)
              .toList();

          // Movimientos de TODOS los remitos + notas C/D con el FIFO unificado
          // del provider: aplica pagos + notas de crédito como crédito y
          // contempla las notas de débito como deuda. Así la lista explica el
          // saldo real (remitos + débitos − pagos − créditos): las ND suman
          // deuda y las NC restan, y no reaparecen remitos ya saldados por una
          // nota de crédito.
          final buckets = app.bucketsDeudaCliente(_cliente);
          final movimientosVisibles = <Map<String, dynamic>>[];
          for (final b in buckets) {
            final saldado = b.deuda <= 0;
            final diasVencido =
                saldado ? 0 : DateTime.now().difference(b.vencimiento).inDays;
            if (b.remito != null) {
              movimientosVisibles.add({
                'tipo': 'remito',
                'fecha': b.remito!.fecha,
                'remito': b.remito,
                'saldado': saldado,
                'deuda': b.deuda,
                'diasVencido': diasVencido,
              });
            } else if (b.notaDebito != null) {
              movimientosVisibles.add({
                'tipo': 'nd',
                'fecha': b.notaDebito!.fecha,
                'nota': b.notaDebito,
                'saldado': saldado,
                'deuda': b.deuda,
                'diasVencido': diasVencido,
              });
            }
          }
          // Notas de crédito: crédito a favor del cliente (restan al saldo).
          for (final n in notasCliente.where((n) => n.esCredito)) {
            movimientosVisibles.add({
              'tipo': 'nc',
              'fecha': n.fecha,
              'nota': n,
              'saldado': false,
              'deuda': 0.0,
              'diasVencido': 0,
            });
          }

          // Ordenar del más reciente al más antiguo
          movimientosVisibles.sort((a, b) =>
              (b['fecha'] as DateTime).compareTo(a['fecha'] as DateTime));

          final cantVencidos = movimientosVisibles
              .where((m) =>
                  (m['tipo'] as String) != 'nc' &&
                  !(m['saldado'] as bool) &&
                  (m['diasVencido'] as int) > 0)
              .length;

          // Deuda vencida = todos los buckets vencidos (remitos + notas de
          // débito), igual que el provider. Así coincide con el saldo cuando
          // toda la deuda está vencida; el cálculo por remitos solo omitía las
          // notas de débito.
          final deudaVencida = app.saldoVencidoCliente(_cliente.id);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Tarjeta de info del cliente ──
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor:
                                AppTheme.primary.withOpacity(0.1),
                            child: Text(
                              _cliente.nombreRazonSocial
                                  .substring(0, 1)
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(_cliente.nombreRazonSocial,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                                if (vendedor != null)
                                  Text(
                                    'Vendedor: ${vendedor.nombreCompleto}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color:
                                            AppTheme.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Info de contacto
                      if (_cliente.telefono.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            onTap: () =>
                                abrirWhatsApp(_cliente.telefono),
                            child: Row(
                              children: [
                                const Icon(Icons.chat,
                                    size: 16,
                                    color: Color(0xFF25D366)),
                                const SizedBox(width: 8),
                                const Text('Teléfono: ',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            AppTheme.textSecondary)),
                                Expanded(
                                  child: Text(
                                    _cliente.telefono,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF128C7E),
                                        decoration:
                                            TextDecoration.underline),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      _InfoRow(
                          icon: Icons.schedule_outlined,
                          label: 'Plazo de pago',
                          value: '${_cliente.plazoPagoDias} días'),
                      if (_cliente.ubicacion.isNotEmpty)
                        _InfoRow(
                            icon: Icons.location_on_outlined,
                            label: 'Ubicación',
                            value: _cliente.ubicacion),
                      if (_cliente.ubicacionUrl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: InkWell(
                            onTap: () => _abrirMaps(
                                _cliente.ubicacionUrl),
                            child: Row(
                              children: [
                                const Icon(Icons.map_outlined,
                                    size: 16,
                                    color: AppTheme.info),
                                const SizedBox(width: 8),
                                const Text('Ver en Google Maps',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.info,
                                        decoration: TextDecoration
                                            .underline)),
                              ],
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Resumen de cuenta
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceAround,
                        children: [
                          _Stat(
                            label: 'Saldo',
                            value: formatPesos(saldo),
                            color: saldo > 0
                                ? AppTheme.danger
                                : AppTheme.success,
                          ),
                          _Stat(
                            label: 'Deuda vencida',
                            value: formatPesos(deudaVencida),
                            color: deudaVencida > 0
                                ? AppTheme.danger
                                : AppTheme.success,
                          ),
                          _Stat(
                            label: 'Vencidos',
                            value: '$cantVencidos',
                            color: cantVencidos > 0
                                ? AppTheme.danger
                                : AppTheme.success,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Botones: pago + estado de cuenta ──
              Row(
                children: [
                  if (saldo > 0)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PagoFormScreen(clienteInicial: _cliente),
                          ),
                        ),
                        icon: const Icon(Icons.payments, size: 18),
                        label: const Text('Registrar pago'),
                      ),
                    ),
                  if (saldo > 0) const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _exportarEstadoCuenta(
                          context, app, _cliente, vendedor,
                          remitosCliente, pagosCliente, saldo),
                      icon: const Icon(Icons.description_outlined,
                          size: 18),
                      label: const Text('Estado de cuenta'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ── Movimientos ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Remitos y notas',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary)),
                  Text('${movimientosVisibles.length} en total',
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textHint)),
                ],
              ),
              const SizedBox(height: 10),

              if (movimientosVisibles.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 40, color: AppTheme.textHint),
                        const SizedBox(height: 8),
                        const Text('Sin remitos cargados',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                )
              else
                ...movimientosVisibles.map((m) {
                  final tipo = m['tipo'] as String;

                  // ── Nota de crédito: crédito a favor (resta al saldo) ──
                  if (tipo == 'nc') {
                    final nota = m['nota'] as NotaCreditoDebito;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(
                                color: AppTheme.success, width: 3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.remove_circle_outline,
                                        size: 16, color: AppTheme.success),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${nota.numeroFormateado} · ${formatFecha(nota.fecha)}',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                                const StatusPill(
                                  text: 'Crédito',
                                  type: StatusType.success,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    nota.motivo.isEmpty
                                        ? 'Nota de crédito'
                                        : nota.motivo,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary),
                                  ),
                                ),
                                Text(
                                  '- ${formatPesos(nota.monto)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.success,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // ── Remito o nota de débito: cargo que suma deuda ──
                  final esNd = tipo == 'nd';
                  final Remito? remito =
                      esNd ? null : m['remito'] as Remito;
                  final NotaCreditoDebito? notaDeb =
                      esNd ? m['nota'] as NotaCreditoDebito : null;
                  final saldado = m['saldado'] as bool;
                  final deuda = m['deuda'] as double;
                  final diasVencido = m['diasVencido'] as int;
                  final estaVencido = !saldado && diasVencido > 0;

                  final numero = esNd
                      ? notaDeb!.numeroFormateado
                      : remito!.numeroFormateado;
                  final fecha = esNd ? notaDeb!.fecha : remito!.fecha;
                  final total = esNd ? notaDeb!.monto : remito!.totalPesos;

                  final Color borderColor;
                  if (saldado) {
                    borderColor = AppTheme.success;
                  } else if (estaVencido) {
                    borderColor = AppTheme.danger;
                  } else {
                    borderColor = AppTheme.warning;
                  }

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: esNd
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RemitoFormScreen(
                                      remitoInicial: remito),
                                ),
                              );
                            },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: borderColor,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      saldado
                                          ? Icons.check_circle
                                          : (estaVencido
                                              ? Icons.error_outline
                                              : Icons.schedule),
                                      size: 16,
                                      color: borderColor,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$numero · ${formatFecha(fecha)}',
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                                if (saldado)
                                  const StatusPill(
                                    text: 'Saldado',
                                    type: StatusType.success,
                                  )
                                else if (estaVencido)
                                  StatusPill(
                                    text: 'Vencido $diasVencido d',
                                    type: StatusType.danger,
                                  )
                                else
                                  const StatusPill(
                                    text: 'Pendiente',
                                    type: StatusType.warning,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        esNd
                                            ? 'Débito: ${formatPesos(total)}'
                                            : 'Total: ${formatPesos(total)}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color:
                                                AppTheme.textSecondary),
                                      ),
                                      Text(
                                        esNd
                                            ? (notaDeb!.motivo.isEmpty
                                                ? 'Nota de débito'
                                                : notaDeb.motivo)
                                            : formatKg(remito!.totalKg),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color:
                                                AppTheme.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!saldado)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      const Text('Deuda restante',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: AppTheme
                                                  .textSecondary)),
                                      Text(
                                        formatPesos(deuda),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.danger,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Future<void> _abrirMaps(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _exportarEstadoCuenta(
    BuildContext context,
    AppProvider app,
    Cliente cliente,
    Vendedor? vendedor,
    List<Remito> remitos,
    List<Pago> pagos,
    double saldo,
  ) async {
    final notasCliente = app.notasCreditoDebito
        .where((n) => n.clienteId == cliente.id)
        .toList();
    await EstadoCuentaService.generarYCompartir(
      cliente: cliente,
      vendedor: vendedor,
      remitos: remitos,
      pagos: pagos,
      saldoTotal: saldo,
      notasCD: notasCliente,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textHint),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Stat({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: color ?? AppTheme.textPrimary,
            )),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }
}
