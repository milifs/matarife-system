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

          // Obtener remitos del cliente
          final remitosCliente = app.remitos
              .where((r) => r.clienteId == _cliente.id)
              .toList();

          // Obtener pagos del cliente
          final pagosCliente = app.pagos
              .where((p) => p.clienteId == _cliente.id)
              .toList();

          final totalRemitos = remitosCliente.fold<double>(
              0, (sum, r) => sum + r.totalPesos);
          final totalPagos = pagosCliente.fold<double>(
              0, (sum, p) => sum + p.montoTotal);

          // Calcular estado de TODOS los remitos (saldados + pendientes) con FIFO
          final remitosConEstado = <Map<String, dynamic>>[];
          double pagosAplicados = totalPagos;

          // Ordenar remitos del más antiguo al más nuevo para aplicar FIFO
          final remitosOrdenados = [...remitosCliente];
          remitosOrdenados.sort((a, b) => a.fecha.compareTo(b.fecha));

          for (final remito in remitosOrdenados) {
            if (pagosAplicados >= remito.totalPesos) {
              // Remito completamente saldado
              pagosAplicados -= remito.totalPesos;
              remitosConEstado.add({
                'remito': remito,
                'saldado': true,
                'deuda': 0.0,
                'diasVencido': 0,
              });
            } else {
              // Remito con deuda pendiente
              final deudaRestante = remito.totalPesos - pagosAplicados;
              pagosAplicados = 0;

              final vencimiento = remito.fecha
                  .add(Duration(days: _cliente.plazoPagoDias));
              final diasVencido =
                  DateTime.now().difference(vencimiento).inDays;

              remitosConEstado.add({
                'remito': remito,
                'saldado': false,
                'deuda': deudaRestante,
                'diasVencido': diasVencido,
              });
            }
          }

          // Ordenar del más reciente al más antiguo
          final movimientosVisibles = [...remitosConEstado];
          movimientosVisibles.sort((a, b) =>
              (b['remito'] as Remito).fecha.compareTo(
                  (a['remito'] as Remito).fecha));

          final cantVencidos = remitosConEstado
              .where((m) =>
                  !(m['saldado'] as bool) && (m['diasVencido'] as int) > 0)
              .length;

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
                        _InfoRow(
                            icon: Icons.phone_outlined,
                            label: 'Teléfono',
                            value: _cliente.telefono),
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
                              label: 'Total remitos',
                              value: formatPesos(totalRemitos)),
                          _Stat(
                              label: 'Total pagado',
                              value: formatPesos(totalPagos),
                              color: AppTheme.success),
                          _Stat(
                            label: 'Saldo',
                            value: formatPesos(saldo),
                            color: saldo > 0
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
                  const Text('Remitos',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary)),
                  Text('${remitosCliente.length} en total',
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
                  final remito = m['remito'] as Remito;
                  final saldado = m['saldado'] as bool;
                  final deuda = m['deuda'] as double;
                  final diasVencido = m['diasVencido'] as int;
                  final estaVencido = !saldado && diasVencido > 0;

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
                      onTap: () {
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
                                      '${remito.numeroFormateado} · ${formatFecha(remito.fecha)}',
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
                                        'Total: ${formatPesos(remito.totalPesos)}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color:
                                                AppTheme.textSecondary),
                                      ),
                                      Text(
                                        formatKg(remito.totalKg),
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
    await EstadoCuentaService.generarYCompartir(
      cliente: cliente,
      vendedor: vendedor,
      remitos: remitos,
      pagos: pagos,
      saldoTotal: saldo,
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
