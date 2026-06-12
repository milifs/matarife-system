// ============================================================
// PANTALLA PRINCIPAL - Dashboard con KPIs por tipo de carne
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';
import 'vendedor_detalle_screen.dart';
import 'costos_semana_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _semanaRef = DateTime.now();

  DateTime get _lunesRef {
    final d = _semanaRef.subtract(Duration(days: _semanaRef.weekday - 1));
    return DateTime(d.year, d.month, d.day);
  }

  bool get _esSemanaActual {
    final hoy = DateTime.now();
    final lunesHoy = hoy.subtract(Duration(days: hoy.weekday - 1));
    final lunesHoyNorm = DateTime(lunesHoy.year, lunesHoy.month, lunesHoy.day);
    return _lunesRef.isAtSameMomentAs(lunesHoyNorm);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matarife - terceros'),
        actions: [
          if (app.tienePermiso('gestionar_costos'))
            IconButton(
              icon: const Icon(Icons.savings_outlined),
              tooltip: 'Costos por semana',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CostosSemanaScreen()),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => context.read<AppProvider>().cargarDatos(),
          ),
        ],
      ),
      body: Consumer<AppProvider>(
        builder: (context, app, _) {
          if (app.loading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (app.error != null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: AppTheme.danger),
                  const SizedBox(height: 12),
                  Text(app.error!,
                      textAlign: TextAlign.center,
                      style:
                          const TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => app.cargarDatos(),
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          final vencidos = app.clientesConSaldoVencido();
          final kgPorTipo = app.kgVendidosSemanasPorTipo(_semanaRef);
          final gananciaPorTipo = app.gananciaSemanalPorTipo(_semanaRef);
          final costoSemana = app.costoParaFecha(_semanaRef);

          final kgNovillo = kgPorTipo['Novillo'] ?? 0;
          final kgCerdo = kgPorTipo['Cerdo'] ?? 0;
          final gananciaNovillo = gananciaPorTipo['Novillo'] ?? 0;
          final gananciaCerdo = gananciaPorTipo['Cerdo'] ?? 0;
          final gananciaTotal = gananciaNovillo + gananciaCerdo;

          return RefreshIndicator(
            onRefresh: () => app.cargarDatos(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Semana anterior',
                      onPressed: () => setState(() =>
                          _semanaRef =
                              _semanaRef.subtract(const Duration(days: 7))),
                    ),
                    Text(
                      'Semana ${formatRangoSemana(_semanaRef)}',
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Semana siguiente',
                      onPressed: _esSemanaActual
                          ? null
                          : () => setState(() =>
                              _semanaRef =
                                  _semanaRef.add(const Duration(days: 7))),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Saldo a cobrar ──
                _KpiCard(
                  label: 'Saldo total a cobrar',
                  value: formatPesos(app.saldoTotal),
                  valueColor: AppTheme.danger,
                  badge: vencidos.isNotEmpty
                      ? '${vencidos.length} vencidos'
                      : null,
                  badgeType: StatusType.danger,
                ),
                const SizedBox(height: 10),

                if (app.esAdmin) ...[
                  // ── Kg vendidos por tipo ──
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                          label: 'Kg novillo semana',
                          value: formatKg(kgNovillo),
                          valueColor: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _KpiCard(
                          label: 'Kg cerdo semana',
                          value: formatKg(kgCerdo),
                          valueColor: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Costo por kg por tipo ──
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                          label: 'Costo/kg novillo',
                          value: costoSemana != null
                              ? formatPesos(costoSemana.costoPorKgNovillo)
                              : '--',
                          valueColor: AppTheme.textPrimary,
                          badge: costoSemana == null ? 'Cargar' : 'Editar',
                          badgeType: costoSemana == null ? StatusType.warning : StatusType.info,
                          onBadgeTap: () =>
                              _mostrarCargaCosto(context, app),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _KpiCard(
                          label: 'Costo/kg cerdo',
                          value: costoSemana != null
                              ? formatPesos(costoSemana.costoPorKgCerdo)
                              : '--',
                          valueColor: AppTheme.textPrimary,
                          badge: costoSemana == null ? 'Cargar' : 'Editar',
                          badgeType: costoSemana == null ? StatusType.warning : StatusType.info,
                          onBadgeTap: () =>
                              _mostrarCargaCosto(context, app),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Ganancia por tipo ──
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                          label: 'Ganancia novillo',
                          value: costoSemana != null
                              ? formatPesos(gananciaNovillo)
                              : '--',
                          valueColor: AppTheme.success,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _KpiCard(
                          label: 'Ganancia cerdo',
                          value: costoSemana != null
                              ? formatPesos(gananciaCerdo)
                              : '--',
                          valueColor: AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Ganancia total ──
                  _KpiCard(
                    label: 'Ganancia total semanal',
                    value: costoSemana != null
                        ? formatPesos(gananciaTotal)
                        : '--',
                    valueColor: AppTheme.success,
                    badge: costoSemana == null
                        ? 'Sin costo cargado'
                        : null,
                    badgeType: StatusType.warning,
                    onBadgeTap: _esSemanaActual
                        ? () => _mostrarCargaCosto(context, app)
                        : null,
                  ),
                ],

                const SizedBox(height: 24),

                // ── Vendedores ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Vendedores - saldo pendiente',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary)),
                    Text('${app.vendedores.length}',
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textHint)),
                  ],
                ),
                const SizedBox(height: 10),

                if (app.vendedores.isEmpty)
                  _EmptyState(
                    icon: Icons.people_outline,
                    message: 'No hay vendedores cargados',
                    action: 'Agregá uno desde la pestaña Vendedores',
                  )
                else
                  ...app.vendedores.map((v) {
                    final saldo = app.getSaldoVendedor(v.id);
                    final clientesVend = app.clientesDeVendedor(v.id);
                    final vencidosVend =
                        app.clientesVencidosDeVendedor(v.id);

                    return _VendedorCard(
                      nombre: v.nombreCompleto,
                      cantClientes: clientesVend.length,
                      saldo: saldo,
                      vencidos: vencidosVend,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              VendedorDetalleScreen(vendedor: v),
                        ),
                      ),
                    );
                  }),

                const SizedBox(height: 80),
              ],
            ),
          );
        },
      ),
    );
  }

  void _mostrarCargaCosto(BuildContext context, AppProvider app) {
    final costoExistente = app.costoParaFecha(_semanaRef);
    final novilloCtrl = TextEditingController(
      text: costoExistente?.costoPorKgNovillo.toStringAsFixed(0) ?? '',
    );
    final cerdoCtrl = TextEditingController(
      text: costoExistente?.costoPorKgCerdo.toStringAsFixed(0) ?? '',
    );

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
            const Text('Costo por kg esta semana',
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Semana ${formatRangoSemana(_semanaRef)}',
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: novilloCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Costo por kg Novillo (\$)',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cerdoCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Costo por kg Cerdo (\$)',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final novillo = double.tryParse(novilloCtrl.text);
                  final cerdo = double.tryParse(cerdoCtrl.text);
                  if (novillo == null || cerdo == null) return;

                  app.guardarCostoSemana(CostoSemanal(
                    semanaInicio: _lunesRef,
                    costoPorKgNovillo: novillo,
                    costoPorKgCerdo: cerdo,
                  ));

                  Navigator.pop(ctx);
                },
                child: const Text('Guardar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets internos ──

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final String? badge;
  final StatusType? badgeType;
  final VoidCallback? onBadgeTap;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.valueColor,
    this.badge,
    this.badgeType,
    this.onBadgeTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: valueColor)),
            ),
            if (badge != null) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: onBadgeTap,
                child: StatusPill(
                    text: badge!, type: badgeType ?? StatusType.info),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _VendedorCard extends StatelessWidget {
  final String nombre;
  final int cantClientes;
  final double saldo;
  final int vencidos;
  final VoidCallback onTap;

  const _VendedorCard({
    required this.nombre,
    required this.cantClientes,
    required this.saldo,
    required this.vencidos,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nombre,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('$cantClientes clientes',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatPesos(saldo),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color:
                            saldo > 0 ? AppTheme.danger : AppTheme.success,
                      )),
                  const SizedBox(height: 4),
                  if (vencidos > 0)
                    StatusPill(
                        text: '$vencidos vencidos',
                        type: StatusType.danger)
                  else if (saldo <= 0)
                    const StatusPill(
                        text: 'Al día', type: StatusType.success)
                  else
                    const StatusPill(
                        text: 'En plazo', type: StatusType.info),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  color: AppTheme.textHint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String action;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(icon, size: 40, color: AppTheme.textHint),
            const SizedBox(height: 12),
            Text(message,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(action,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}
