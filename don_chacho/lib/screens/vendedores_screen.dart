// ============================================================
// ABM VENDEDORES - Alta, baja, modificación
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';
import 'vendedor_detalle_screen.dart';

class VendedoresScreen extends StatelessWidget {
  const VendedoresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vendedores'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () => _mostrarFormVendedor(context),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, app, _) {
          if (app.vendedores.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.people_outline,
                      size: 64, color: AppTheme.textHint),
                  const SizedBox(height: 16),
                  const Text('No hay vendedores',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  const Text('Tocá + para agregar el primero',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => _mostrarFormVendedor(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Agregar vendedor'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: app.vendedores.length,
            itemBuilder: (context, index) {
              final v = app.vendedores[index];
              final saldo = app.getSaldoVendedor(v.id);
              final clientes = app.clientesDeVendedor(v.id);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VendedorDetalleScreen(vendedor: v),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Avatar con iniciales
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: AppTheme.primary.withOpacity(0.1),
                          child: Text(
                            '${v.nombre[0]}${v.apellido[0]}',
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(v.nombreCompleto,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Text(
                                '${clientes.length} clientes  •  ${v.telefono}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
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
                          ],
                        ),
                        const SizedBox(width: 4),
                        PopupMenuButton(
                          icon: const Icon(Icons.more_vert,
                              color: AppTheme.textHint, size: 20),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'editar',
                              child: Text('Editar'),
                            ),
                            const PopupMenuItem(
                              value: 'eliminar',
                              child: Text('Eliminar',
                                  style:
                                      TextStyle(color: AppTheme.danger)),
                            ),
                          ],
                          onSelected: (action) {
                            if (action == 'editar') {
                              _mostrarFormVendedor(context, vendedor: v);
                            } else if (action == 'eliminar') {
                              _confirmarEliminar(context, v);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _mostrarFormVendedor(BuildContext context, {Vendedor? vendedor}) {
    final nombreCtrl =
        TextEditingController(text: vendedor?.nombre ?? '');
    final apellidoCtrl =
        TextEditingController(text: vendedor?.apellido ?? '');
    final telefonoCtrl =
        TextEditingController(text: vendedor?.telefono ?? '');
    final esEdicion = vendedor != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              esEdicion ? 'Editar vendedor' : 'Nuevo vendedor',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nombreCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: apellidoCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Apellido'),
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
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (nombreCtrl.text.isEmpty ||
                      apellidoCtrl.text.isEmpty) {
                    return;
                  }

                  final app = context.read<AppProvider>();

                  if (esEdicion) {
                    vendedor!.nombre = nombreCtrl.text.trim();
                    vendedor.apellido = apellidoCtrl.text.trim();
                    vendedor.telefono = telefonoCtrl.text.trim();
                    app.editarVendedor(vendedor);
                  } else {
                    app.agregarVendedor(Vendedor(
                      nombre: nombreCtrl.text.trim(),
                      apellido: apellidoCtrl.text.trim(),
                      telefono: telefonoCtrl.text.trim(),
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
    );
  }

  void _confirmarEliminar(BuildContext context, Vendedor vendedor) {
    final app = context.read<AppProvider>();
    final clientes = app.clientesDeVendedor(vendedor.id);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar vendedor'),
        content: Text(
          clientes.isNotEmpty
              ? '${vendedor.nombreCompleto} tiene ${clientes.length} clientes asignados. '
                  '¿Estás seguro de eliminarlo?'
              : '¿Eliminar a ${vendedor.nombreCompleto}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              app.eliminarVendedor(vendedor.id);
              Navigator.pop(ctx);
            },
            child: const Text('Eliminar',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
