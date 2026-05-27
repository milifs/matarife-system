// ============================================================
// DETALLE VENDEDOR - Clientes, saldos, agregar cliente
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';
import '../services/estado_cuenta_service.dart';
import 'cliente_detalle_screen.dart';

class VendedorDetalleScreen extends StatelessWidget {
  final Vendedor vendedor;

  const VendedorDetalleScreen({super.key, required this.vendedor});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(vendedor.nombreCompleto),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf,
                color: AppTheme.primary),
            tooltip: 'Reporte del vendedor',
            onPressed: () => _exportarReporteVendedor(context),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, app, _) {
          final clientes = app.clientesDeVendedor(vendedor.id);
          final saldoTotal = app.getSaldoVendedor(vendedor.id);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Resumen del vendedor ──
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: AppTheme.primary.withOpacity(0.1),
                        child: Text(
                          '${vendedor.nombre[0]}${vendedor.apellido[0]}',
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(vendedor.nombreCompleto,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      Text(vendedor.telefono,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary)),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _Stat(
                              label: 'Clientes',
                              value: '${clientes.length}'),
                          _Stat(
                            label: 'Saldo total',
                            value: formatPesosCorto(saldoTotal),
                            color: saldoTotal > 0
                                ? AppTheme.danger
                                : AppTheme.success,
                          ),
                          _Stat(
                            label: 'Vencidos',
                            value:
                                '${app.clientesVencidosDeVendedor(vendedor.id)}',
                            color: app.clientesVencidosDeVendedor(
                                        vendedor.id) >
                                    0
                                ? AppTheme.danger
                                : AppTheme.success,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Lista de clientes ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Clientes',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        _mostrarFormCliente(context, vendedor.id),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Agregar'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              if (clientes.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(Icons.store_outlined,
                            size: 40, color: AppTheme.textHint),
                        const SizedBox(height: 8),
                        const Text('Sin clientes',
                            style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary)),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () => _mostrarFormCliente(
                              context, vendedor.id),
                          child: const Text('Agregar primer cliente'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...clientes.map((c) {
                  final saldo = app.getSaldoCliente(c.id);
                  final vencidos = app.remitosVencidosCliente(c.id);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ClienteDetalleScreen(cliente: c),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(c.nombreRazonSocial,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 2),
                                  Text(
                                    vencidos > 0
                                        ? '$vencidos remito${vencidos == 1 ? '' : 's'} vencido${vencidos == 1 ? '' : 's'}'
                                        : 'Sin remitos vencidos',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: vencidos > 0
                                            ? AppTheme.danger
                                            : AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              formatPesosCorto(saldo),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: saldo > 0
                                    ? AppTheme.danger
                                    : AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            PopupMenuButton(
                              icon: const Icon(Icons.more_vert,
                                  size: 18,
                                  color: AppTheme.textHint),
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                    value: 'editar',
                                    child: Text('Editar')),
                                const PopupMenuItem(
                                  value: 'eliminar',
                                  child: Text('Eliminar',
                                      style: TextStyle(
                                          color: AppTheme.danger)),
                                ),
                              ],
                              onSelected: (action) {
                                if (action == 'editar') {
                                  _mostrarFormCliente(context,
                                      vendedor.id,
                                      cliente: c);
                                } else if (action == 'eliminar') {
                                  _confirmarEliminarCliente(
                                      context, c);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  void _mostrarFormCliente(BuildContext context, String vendedorId,
      {Cliente? cliente}) {
    final nombreCtrl = TextEditingController(
        text: cliente?.nombreRazonSocial ?? '');
    final telefonoCtrl =
        TextEditingController(text: cliente?.telefono ?? '');
    final plazoCtrl = TextEditingController(
        text: cliente?.plazoPagoDias.toString() ?? '7');
    final ubicacionCtrl =
        TextEditingController(text: cliente?.ubicacion ?? '');
    final ubicacionUrlCtrl =
        TextEditingController(text: cliente?.ubicacionUrl ?? '');
    final esEdicion = cliente != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                esEdicion ? 'Editar cliente' : 'Nuevo cliente',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Vendedor: ${vendedor.nombreCompleto}',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nombreCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Nombre / Razón social'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: telefonoCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  prefixText: '+54 ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: plazoCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Plazo de pago (días)',
                  suffixText: 'días',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ubicacionCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Ubicación / Dirección',
                  hintText: 'Ej: Av. San Martín 1234, Ciudad',
                  prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ubicacionUrlCtrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Link Google Maps (opcional)',
                  hintText: 'https://maps.google.com/...',
                  prefixIcon: Icon(Icons.map_outlined, size: 20),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (nombreCtrl.text.isEmpty) return;

                    final app = context.read<AppProvider>();
                    final plazo =
                        int.tryParse(plazoCtrl.text) ?? 7;

                    if (esEdicion) {
                      cliente!.nombreRazonSocial =
                          nombreCtrl.text.trim();
                      cliente.telefono = telefonoCtrl.text.trim();
                      cliente.plazoPagoDias = plazo;
                      cliente.ubicacion = ubicacionCtrl.text.trim();
                      cliente.ubicacionUrl = ubicacionUrlCtrl.text.trim();
                      app.editarCliente(cliente);
                    } else {
                      app.agregarCliente(Cliente(
                        nombreRazonSocial: nombreCtrl.text.trim(),
                        telefono: telefonoCtrl.text.trim(),
                        vendedorId: vendedorId,
                        plazoPagoDias: plazo,
                        ubicacion: ubicacionCtrl.text.trim(),
                        ubicacionUrl: ubicacionUrlCtrl.text.trim(),
                      ));
                    }

                    Navigator.pop(ctx);
                  },
                  child: Text(esEdicion ? 'Guardar' : 'Agregar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmarEliminarCliente(
      BuildContext context, Cliente cliente) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cliente'),
        content: Text(
            '¿Eliminar a ${cliente.nombreRazonSocial}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              context.read<AppProvider>().eliminarCliente(cliente.id);
              Navigator.pop(ctx);
            },
            child: const Text('Eliminar',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportarReporteVendedor(BuildContext context) async {
    final app = context.read<AppProvider>();
    final clientes = app.clientesDeVendedor(vendedor.id);
    final remitos = app.remitos;
    final pagos = app.pagos;

    await EstadoCuentaService.generarReporteVendedor(
      vendedor: vendedor,
      clientes: clientes,
      remitos: remitos,
      pagos: pagos,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reporte generado'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
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
              fontSize: 20,
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
