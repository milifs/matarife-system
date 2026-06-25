// ============================================================
// PANTALLA CLIENTES - Lista general con filtros
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';
import 'cliente_detalle_screen.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  String? _filtroVendedorId;
  String? _filtroClienteId;
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
      ),
      body: Consumer<AppProvider>(
        builder: (context, app, _) {
          var clientes = app.clientes.toList();

          // Aplicar filtros
          if (_filtroVendedorId != null) {
            clientes = clientes
                .where((c) => c.vendedorId == _filtroVendedorId)
                .toList();
          }
          if (_filtroClienteId != null) {
            clientes = clientes
                .where((c) => c.id == _filtroClienteId)
                .toList();
          } else if (_busqueda.isNotEmpty) {
            clientes = clientes
                .where((c) => c.nombreRazonSocial
                    .toLowerCase()
                    .contains(_busqueda.toLowerCase()))
                .toList();
          }

          return Column(
            children: [
              // ── Barra de búsqueda ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  onChanged: (v) => setState(() {
                    _busqueda = v;
                    _filtroClienteId = null;
                  }),
                  decoration: InputDecoration(
                    hintText: 'Buscar cliente...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Builder(builder: (context) {
                  var lista = (_filtroVendedorId != null
                          ? app.clientes
                              .where((c) => c.vendedorId == _filtroVendedorId)
                              .toList()
                          : app.clientes.toList())
                    ..sort((a, b) =>
                        a.nombreRazonSocial.compareTo(b.nombreRazonSocial));
                  if (_busqueda.isNotEmpty) {
                    final q = _busqueda.toLowerCase();
                    lista = lista
                        .where((c) =>
                            c.nombreRazonSocial.toLowerCase().contains(q))
                        .toList();
                  }
                  return DropdownButtonFormField<String>(
                    value: lista.any((c) => c.id == _filtroClienteId)
                        ? _filtroClienteId
                        : null,
                    decoration: InputDecoration(
                      labelText: 'Cliente',
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
                      ...lista.map((c) {
                        final v = app.vendedorPorId(c.vendedorId);
                        return DropdownMenuItem(
                          value: c.id,
                          child: Text(
                            '${c.nombreRazonSocial} (${v?.apellido ?? ""})',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (v) => setState(() => _filtroClienteId = v),
                  );
                }),
              ),

              // ── Filtro por vendedor ──
              if (app.vendedores.length > 1)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      _FilterChip(
                        label: 'Todos',
                        selected: _filtroVendedorId == null,
                        onTap: () => setState(() {
                          _filtroVendedorId = null;
                          _filtroClienteId = null;
                        }),
                      ),
                      ...(List.of(app.vendedores)
                            ..sort((a, b) => a.nombreCompleto
                                .compareTo(b.nombreCompleto)))
                          .map((v) => _FilterChip(
                            label: v.nombreCompleto,
                            selected: _filtroVendedorId == v.id,
                            onTap: () => setState(() {
                              _filtroVendedorId = v.id;
                              _filtroClienteId = null;
                            }),
                          )),
                    ],
                  ),
                ),

              // ── Lista ──
              Expanded(
                child: clientes.isEmpty
                    ? const Center(
                        child: Text('No hay clientes',
                            style: TextStyle(
                                color: AppTheme.textSecondary)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: clientes.length,
                        itemBuilder: (context, index) {
                          final c = clientes[index];
                          final saldo = app.getSaldoCliente(c.id);
                          final vendedor =
                              app.vendedorPorId(c.vendedorId);
                          final vencidos = app.remitosVencidosCliente(c.id);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ClienteDetalleScreen(cliente: c),
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
                                                  fontWeight:
                                                      FontWeight.w500)),
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
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right,
                                        size: 20,
                                        color: AppTheme.textHint),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : AppTheme.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.border,
              width: 0.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
