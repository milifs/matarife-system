// ============================================================
// ABM DE PROVEEDORES
// ============================================================
// Ficha mínima: nombre + los tres valores que se repiten carga a carga
// (desvaste, precio del kg vivo y rinde asegurado). Esos valores son el
// DEFAULT del proveedor: se copian a la carga nueva y ahí quedan editables,
// porque el precio cambia seguido y no queremos que al actualizarlo se
// recalculen las cargas viejas.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';

class GestionProveedoresScreen extends StatefulWidget {
  const GestionProveedoresScreen({super.key});

  @override
  State<GestionProveedoresScreen> createState() =>
      _GestionProveedoresScreenState();
}

class _GestionProveedoresScreenState extends State<GestionProveedoresScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Proveedores')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editar(null),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo proveedor'),
      ),
      body: Consumer<AppProvider>(
        builder: (context, app, _) {
          final lista = app.proveedores;
          if (lista.isEmpty) {
            return const Center(
              child: Text(
                'No hay proveedores cargados',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: lista.length,
            itemBuilder: (context, i) {
              final p = lista[i];
              final saldo = app.saldoProveedor(p.id);
              final cargas = app.cargasDeProveedor(p.id).length;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.nombre,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!p.activo)
                        const StatusPill(
                          text: 'Inactivo',
                          type: StatusType.info,
                        ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Desvaste ${formatPorcentaje(p.desvastePorcentaje)} · '
                          'Vivo ${formatPesos(p.precioKgVivo)}/kg · '
                          'Rinde ${formatPorcentaje(p.rindeAsegurado)}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cargas == 0
                              ? 'Sin cargas'
                              : '$cargas carga(s) · ${saldo < -0.5 ? "se le debe ${formatPesos(saldo.abs())}" : "saldado"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: saldo < -0.5
                                ? AppTheme.danger
                                : AppTheme.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _editar(p),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 20, color: AppTheme.danger),
                        onPressed: () => _eliminar(p),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editar(Proveedor? proveedor) async {
    final esNuevo = proveedor == null;
    final nombreCtrl = TextEditingController(text: proveedor?.nombre ?? '');
    final desvasteCtrl = TextEditingController(
        text: (proveedor?.desvastePorcentaje ?? 5).toString());
    final precioCtrl = TextEditingController(
        text: (proveedor?.precioKgVivo ?? 0).toString());
    final rindeCtrl = TextEditingController(
        text: (proveedor?.rindeAsegurado ?? 58).toString());
    var activo = proveedor?.activo ?? true;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(esNuevo ? 'Nuevo proveedor' : 'Editar proveedor'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nombreCtrl,
                  autofocus: esNuevo,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: desvasteCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Desvaste %',
                    helperText: '5 = se paga el 95% del peso vivo',
                    suffixText: '%',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: precioCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Precio por kg vivo',
                    prefixText: '\$ ',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rindeCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Rinde asegurado %',
                    helperText: 'El rinde que promete el proveedor',
                    suffixText: '%',
                  ),
                ),
                if (!esNuevo) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Activo', style: TextStyle(fontSize: 14)),
                    subtitle: const Text(
                      'Los inactivos no aparecen al cargar una compra',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: activo,
                    onChanged: (v) => setLocal(() => activo = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (nombreCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (guardado != true || !mounted) return;

    final app = context.read<AppProvider>();
    final nuevo = Proveedor(
      id: proveedor?.id,
      nombre: nombreCtrl.text.trim(),
      desvastePorcentaje: _aDouble(desvasteCtrl.text, 5),
      precioKgVivo: _aDouble(precioCtrl.text, 0),
      rindeAsegurado: _aDouble(rindeCtrl.text, 58),
      activo: activo,
      creadoEn: proveedor?.creadoEn,
    );
    final ok = await app.guardarProveedor(nuevo, esNuevo: esNuevo);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Proveedor guardado' : 'No se pudo guardar'),
      ),
    );
  }

  Future<void> _eliminar(Proveedor proveedor) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar proveedor'),
        content: Text('¿Seguro que querés eliminar a ${proveedor.nombre}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final error = await context.read<AppProvider>().eliminarProveedor(
          proveedor.id,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Proveedor eliminado')),
    );
  }
}

double _aDouble(String texto, double porDefecto) =>
    double.tryParse(texto.trim().replaceAll(',', '.')) ?? porDefecto;
