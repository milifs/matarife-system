// ============================================================
// PANTALLA DE CONSULTAS - Ganancias, saldos, vencidos, pagos
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';
import '../services/recibo_service.dart';
import '../services/estado_cuenta_service.dart';
import '../services/ruta_cobranza_service.dart';
import 'pago_form_screen.dart';
import 'remito_form_screen.dart';
import 'nota_pedido_form_screen.dart';

class ConsultasScreen extends StatelessWidget {
  const ConsultasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Consultas'),
          bottom: const TabBar(
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textHint,
            indicatorColor: AppTheme.primary,
            isScrollable: true,
            labelStyle:
                TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            tabs: [
              Tab(text: 'Vencidos'),
              Tab(text: 'Ganancias'),
              Tab(text: 'Saldos'),
              Tab(text: 'Historial'),
              Tab(text: 'Directorio'),
              Tab(text: 'Comisiones'),
              Tab(text: 'Eliminados'),
              Tab(text: 'Reporte'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _VencidosTab(),
            _GananciasTab(),
            _SaldosTab(),
            _HistorialTab(),
            _DirectorioTab(),
            _ComisionesTab(),
            _EliminadosTab(),
            _ReporteTab(),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// TAB 1: VENCIDOS
// ═══════════════════════════════════════════
class _VencidosTab extends StatefulWidget {
  const _VencidosTab();

  @override
  State<_VencidosTab> createState() => _VencidosTabState();
}

class _VencidosTabState extends State<_VencidosTab> {
  String? _filtroVendedorId;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        var vencidos = app.todosRemitosVencidos();
        if (_filtroVendedorId != null) {
          final clientesVendedor =
              app.clientesDeVendedor(_filtroVendedorId!).map((c) => c.id).toSet();
          vencidos = vencidos
              .where((m) => clientesVendedor.contains((m['cliente'] as Cliente).id))
              .toList();
        }
        final totalDeuda = vencidos.fold<double>(
            0, (sum, m) => sum + (m['deuda'] as double));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Filtro vendedor ──
            DropdownButtonFormField<String?>(
              value: _filtroVendedorId,
              decoration: const InputDecoration(
                labelText: 'Vendedor',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos')),
                ...app.vendedores.map((v) => DropdownMenuItem(
                      value: v.id,
                      child: Text(v.nombreCompleto),
                    )),
              ],
              onChanged: (v) => setState(() => _filtroVendedorId = v),
            ),
            const SizedBox(height: 12),
            // ── Resumen ──
            Card(
              color: AppTheme.danger.withOpacity(0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Remitos vencidos',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary)),
                        Text('${vencidos.length}',
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.danger)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Deuda total vencida',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary)),
                        Text(formatPesos(totalDeuda),
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.danger)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (vencidos.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: const [
                      Icon(Icons.check_circle_outline,
                          size: 48, color: AppTheme.success),
                      SizedBox(height: 12),
                      Text('Sin remitos vencidos',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              )
            else
              ...vencidos.map((m) {
                final remito = m['remito'] as Remito;
                final cliente = m['cliente'] as Cliente;
                final vendedor = m['vendedor'] as Vendedor?;
                final diasVencido = m['diasVencido'] as int;
                final deuda = m['deuda'] as double;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: app.tienePermiso('editar_remito')
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    RemitoFormScreen(remitoInicial: remito),
                              ),
                            )
                        : null,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(color: AppTheme.danger, width: 3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${remito.numeroFormateado} · ${formatFecha(remito.fecha)}',
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(height: 3),
                                Text(cliente.nombreRazonSocial,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textSecondary)),
                                if (vendedor != null)
                                  Text(vendedor.nombreCompleto,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textHint)),
                                if (cliente.ubicacionUrl.isNotEmpty)
                                  GestureDetector(
                                    onTap: () async {
                                      final uri = Uri.parse(cliente.ubicacionUrl);
                                      if (await canLaunchUrl(uri)) {
                                        await launchUrl(uri,
                                            mode: LaunchMode.externalApplication);
                                      }
                                    },
                                    child: const Text(
                                      'Ver en Maps',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blue,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              StatusPill(
                                text: 'Vencido $diasVencido d',
                                type: StatusType.danger,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                formatPesos(deuda),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.danger,
                                ),
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
    );
  }
}

// ═══════════════════════════════════════════
// TAB 2: GANANCIAS
// ═══════════════════════════════════════════
class _GananciasTab extends StatefulWidget {
  const _GananciasTab();

  @override
  State<_GananciasTab> createState() => _GananciasTabState();
}

class _GananciasTabState extends State<_GananciasTab> {
  DateTime _desde = _inicioSemanaActual();
  DateTime _hasta = DateTime.now();

  static DateTime _inicioSemanaActual() {
    final hoy = DateTime.now();
    final lunes = hoy.subtract(Duration(days: hoy.weekday - 1));
    return DateTime(lunes.year, lunes.month, lunes.day);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        // Filtrar remitos del rango
        final desdeNorm = DateTime(_desde.year, _desde.month, _desde.day);
        final hastaNorm = DateTime(
            _hasta.year, _hasta.month, _hasta.day, 23, 59, 59);
        final remitosRango = app.remitos
            .where((r) =>
                !r.fecha.isBefore(desdeNorm) &&
                !r.fecha.isAfter(hastaNorm))
            .toList();

        // Calcular kg y venta total
        final kgTotal =
            remitosRango.fold<double>(0, (s, r) => s + r.totalKg);
        final ventaTotal = remitosRango.fold<double>(
            0, (s, r) => s + r.totalPesos);

        // Calcular ganancia por tipo usando costos históricos
        double kgNovillo = 0;
        double kgCerdo = 0;
        double ventaNovillo = 0;
        double ventaCerdo = 0;
        double costoNovillo = 0;
        double costoCerdo = 0;
        bool faltanCostos = false;

        for (final r in remitosRango) {
          final items = app.itemsDeRemito(r.id);
          final costoSemana = app.costoParaFecha(r.fecha);
          for (final item in items) {
            if (item.tipoCarne.toLowerCase() == 'novillo') {
              kgNovillo += item.kgTotal;
              ventaNovillo += item.kgTotal * item.precioPorKg;
              if (costoSemana != null) {
                costoNovillo +=
                    item.kgTotal * costoSemana.costoPorKgNovillo;
              } else {
                faltanCostos = true;
              }
            } else {
              kgCerdo += item.kgTotal;
              ventaCerdo += item.kgTotal * item.precioPorKg;
              if (costoSemana != null) {
                costoCerdo +=
                    item.kgTotal * costoSemana.costoPorKgCerdo;
              } else {
                faltanCostos = true;
              }
            }
          }
        }

        final gananciaNovillo = ventaNovillo - costoNovillo;
        final gananciaCerdo = ventaCerdo - costoCerdo;
        final descuentoTransf = app.descuentoTransferenciasRango(desdeNorm, hastaNorm);
        final gananciaTotal = gananciaNovillo + gananciaCerdo - descuentoTransf;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Filtros de rango ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _DateField(
                            label: 'Desde',
                            value: _desde,
                            onChanged: (d) =>
                                setState(() => _desde = d),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DateField(
                            label: 'Hasta',
                            value: _hasta,
                            onChanged: (d) =>
                                setState(() => _hasta = d),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Atajos rápidos
                    Row(
                      children: [
                        _AtajoChip(
                          label: 'Esta semana',
                          onTap: () => setState(() {
                            _desde = _inicioSemanaActual();
                            _hasta = DateTime.now();
                          }),
                        ),
                        const SizedBox(width: 6),
                        _AtajoChip(
                          label: 'Semana anterior',
                          onTap: () => setState(() {
                            final lunesActual = _inicioSemanaActual();
                            _desde = lunesActual
                                .subtract(const Duration(days: 7));
                            _hasta = lunesActual
                                .subtract(const Duration(days: 1));
                          }),
                        ),
                        const SizedBox(width: 6),
                        _AtajoChip(
                          label: 'Mes actual',
                          onTap: () => setState(() {
                            final hoy = DateTime.now();
                            _desde = DateTime(hoy.year, hoy.month, 1);
                            _hasta = hoy;
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Tarjeta de ganancia global del rango ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ganancia del período',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    Text(
                      '${formatFecha(_desde)} al ${formatFecha(_hasta)}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _StatColumn(
                              label: 'Kg vendidos',
                              value: formatKg(kgTotal)),
                        ),
                        Expanded(
                          child: _StatColumn(
                              label: 'Venta bruta',
                              value: formatPesos(ventaTotal)),
                        ),
                        Expanded(
                          child: _StatColumn(
                            label: 'Ganancia neta',
                            value: formatPesos(gananciaTotal),
                            color: AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                    if (kgNovillo > 0 || kgCerdo > 0) ...[
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      if (kgNovillo > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Novillo · ${formatKg(kgNovillo)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                              ),
                              Text(formatPesos(gananciaNovillo),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.success)),
                            ],
                          ),
                        ),
                      if (kgCerdo > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Cerdo · ${formatKg(kgCerdo)}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                              ),
                              Text(formatPesos(gananciaCerdo),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.success)),
                            ],
                          ),
                        ),
                    ],
                    if (descuentoTransf > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Desc. transferencias',
                            style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary),
                          ),
                          Text(
                            '-${formatPesos(descuentoTransf)}',
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.danger),
                          ),
                        ],
                      ),
                    ],
                    if (faltanCostos) ...[
                      const SizedBox(height: 12),
                      const StatusPill(
                        text:
                            'Faltan costos de algunas semanas del período',
                        type: StatusType.warning,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Ventas por vendedor en el rango ──
            const Text('Ventas por vendedor',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary)),
            const SizedBox(height: 10),
            ...app.vendedores.map((v) {
              final clientesV = app.clientesDeVendedor(v.id);
              final clienteIds = clientesV.map((c) => c.id).toSet();
              final remitosVendedor = remitosRango
                  .where((r) => clienteIds.contains(r.clienteId))
                  .toList();
              final kgVend = remitosVendedor.fold<double>(
                  0, (sum, r) => sum + r.totalKg);
              final ventaVend = remitosVendedor.fold<double>(
                  0, (sum, r) => sum + r.totalPesos);

              if (kgVend == 0) return const SizedBox.shrink();

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(v.nombreCompleto,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500)),
                          Text('${clientesV.length} clientes',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _StatColumn(
                                label: 'Kg', value: formatKg(kgVend)),
                          ),
                          Expanded(
                            child: _StatColumn(
                                label: 'Venta',
                                value: formatPesos(ventaVend)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),

            // ══════════════
            // RANKING POR CLIENTE - rango
            // ══════════════
            const Text('Ventas por cliente',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary)),
            const SizedBox(height: 10),
            ..._buildRankingClientes(app, remitosRango),
          ],
        );
      },
    );
  }

  /// Ranking de clientes por venta en el rango
  List<Widget> _buildRankingClientes(
      AppProvider app, List<Remito> remitosRango) {
    final porCliente = <String, Map<String, double>>{};
    for (final r in remitosRango) {
      porCliente.putIfAbsent(r.clienteId, () => {'kg': 0, 'venta': 0});
      porCliente[r.clienteId]!['kg'] =
          porCliente[r.clienteId]!['kg']! + r.totalKg;
      porCliente[r.clienteId]!['venta'] =
          porCliente[r.clienteId]!['venta']! + r.totalPesos;
    }

    if (porCliente.isEmpty) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined,
                    size: 36, color: AppTheme.textHint),
                const SizedBox(height: 8),
                const Text('Sin ventas en este período',
                    style: TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary)),
              ],
            ),
          ),
        ),
      ];
    }

    final ranking = porCliente.entries.toList()
      ..sort((a, b) =>
          (b.value['venta']!).compareTo(a.value['venta']!));

    return ranking.map((entry) {
      final cliente = app.clientePorId(entry.key);
      final vendedor = cliente != null
          ? app.vendedorPorId(cliente.vendedorId)
          : null;
      final kg = entry.value['kg']!;
      final venta = entry.value['venta']!;

      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cliente?.nombreRazonSocial ?? 'Cliente',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                    Text(
                      '${vendedor?.nombreCompleto ?? ""} · ${formatKg(kg)}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              Text(formatPesos(venta),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }).toList();
  }
}

// ── Campo de fecha con date picker ──
class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const _DateField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2024),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          locale: const Locale('es'),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 10),
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
        ),
        child: Text(
          formatFecha(value),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

class _AtajoChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AtajoChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppTheme.primary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// TAB 2: SALDOS
// ═══════════════════════════════════════════
class _SaldosTab extends StatefulWidget {
  const _SaldosTab();

  @override
  State<_SaldosTab> createState() => _SaldosTabState();
}

class _SaldosTabState extends State<_SaldosTab> {
  bool _soloVencidos = false;
  bool _soloNoVencidos = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        Set<String>? clientesFiltradosIds;
        if (_soloVencidos) {
          clientesFiltradosIds = app
              .clientesConSaldoVencido()
              .map((m) => (m['cliente'] as Cliente).id)
              .toSet();
        } else if (_soloNoVencidos) {
          clientesFiltradosIds = app
              .todosRemitosNoVencidos()
              .map((m) => (m['cliente'] as Cliente).id)
              .toSet();
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Saldo total a cobrar',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    Text(formatPesos(app.saldoTotal),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: app.saldoTotal > 0
                              ? AppTheme.danger
                              : AppTheme.success,
                        )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Solo vencidos'),
                  selected: _soloVencidos,
                  onSelected: (v) => setState(() {
                    _soloVencidos = v;
                    if (v) _soloNoVencidos = false;
                  }),
                  selectedColor: AppTheme.danger.withOpacity(0.15),
                  checkmarkColor: AppTheme.danger,
                ),
                FilterChip(
                  label: const Text('Solo no vencidos'),
                  selected: _soloNoVencidos,
                  onSelected: (v) => setState(() {
                    _soloNoVencidos = v;
                    if (v) _soloVencidos = false;
                  }),
                  selectedColor: AppTheme.info.withOpacity(0.15),
                  checkmarkColor: AppTheme.info,
                ),
              ],
            ),

            const SizedBox(height: 12),
            ...app.vendedores.map((v) {
              var clientesV = app.clientesDeVendedor(v.id);
              if (clientesFiltradosIds != null) {
                clientesV = clientesV
                    .where((c) => clientesFiltradosIds!.contains(c.id))
                    .toList();
              }
              if (clientesV.isEmpty) return const SizedBox.shrink();

              final saldoVend = clientesFiltradosIds != null
                  ? clientesV.fold<double>(
                      0, (sum, c) => sum + app.getSaldoCliente(c.id))
                  : app.getSaldoVendedor(v.id);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                  title: Text(v.nombreCompleto,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500)),
                  subtitle: Text('${clientesV.length} clientes',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: Text(formatPesos(saldoVend),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: saldoVend > 0
                            ? AppTheme.danger
                            : AppTheme.textPrimary,
                      )),
                  children: [
                    const Divider(height: 1),
                    ...clientesV.map((c) {
                      final saldo = app.getSaldoCliente(c.id);
                      return ListTile(
                        dense: true,
                        title: Text(c.nombreRazonSocial,
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                            'Plazo: ${c.plazoPagoDias} días',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary)),
                        trailing: Text(formatPesos(saldo),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: saldo > 0
                                  ? AppTheme.danger
                                  : AppTheme.success,
                            )),
                        onTap: saldo > 0 && app.tienePermiso('crear_pago')
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PagoFormScreen(
                                        clienteInicial: c),
                                  ),
                                )
                            : null,
                      );
                    }),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

// ═══════════════════════════════════════════
// TAB 3: HISTORIAL (Remitos + Pagos unificados)
// ═══════════════════════════════════════════
class _HistorialTab extends StatefulWidget {
  const _HistorialTab();

  @override
  State<_HistorialTab> createState() => _HistorialTabState();
}

class _HistorialTabState extends State<_HistorialTab> {
  String? _filtroVendedorId;
  String? _filtroClienteId;
  String _filtroTipo = 'todos'; // 'todos', 'remito', 'pago', 'ndp'
  DateTime? _filtroDesde;
  DateTime? _filtroHasta;
  final TextEditingController _busquedaCtrl = TextEditingController();
  bool _mostrarSugerencias = false;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        // Armar items unificados
        final items = <_HistorialItem>[];

        if (_filtroTipo == 'todos' || _filtroTipo == 'remito') {
          for (final r in app.remitos) {
            items.add(_HistorialItem(
              tipo: 'remito',
              remito: r,
              fecha: r.fecha,
              numero: r.numero,
              clienteId: r.clienteId,
              monto: r.totalPesos,
            ));
          }
        }
        if (_filtroTipo == 'todos' || _filtroTipo == 'pago') {
          for (final p in app.pagos) {
            items.add(_HistorialItem(
              tipo: 'pago',
              pago: p,
              fecha: p.fecha,
              numero: p.numero,
              clienteId: p.clienteId,
              monto: p.montoTotal,
            ));
          }
        }
        if (_filtroTipo == 'todos' || _filtroTipo == 'ndp') {
          for (final n in app.notasPedido) {
            items.add(_HistorialItem(
              tipo: 'ndp',
              ndp: n,
              fecha: n.fecha,
              numero: n.numero,
              clienteId: n.clienteId ?? '',
              clienteNombreLibre: n.clienteNombreLibre,
              monto: n.totalPesos,
            ));
          }
        }

        // Aplicar filtros
        var itemsFiltrados = items;
        if (_filtroClienteId != null) {
          itemsFiltrados = itemsFiltrados
              .where((i) => i.clienteId == _filtroClienteId)
              .toList();
        } else if (_filtroVendedorId != null) {
          final clienteIds = app
              .clientesDeVendedor(_filtroVendedorId!)
              .map((c) => c.id)
              .toSet();
          itemsFiltrados = itemsFiltrados
              .where((i) =>
                  i.tipo != 'ndp'
                      ? clienteIds.contains(i.clienteId)
                      : (i.clienteId.isNotEmpty
                          ? clienteIds.contains(i.clienteId)
                          : false))
              .toList();
        }
        // Filtro por búsqueda de texto (si no se eligió cliente específico)
        if (_filtroClienteId == null && _busquedaCtrl.text.isNotEmpty) {
          final query = _busquedaCtrl.text.toLowerCase();
          final clienteIdsMatch = app.clientes
              .where((c) =>
                  c.nombreRazonSocial.toLowerCase().contains(query))
              .map((c) => c.id)
              .toSet();
          itemsFiltrados = itemsFiltrados
              .where((i) =>
                  clienteIdsMatch.contains(i.clienteId) ||
                  (i.clienteNombreLibre
                          ?.toLowerCase()
                          .contains(query) ==
                      true))
              .toList();
        }
        if (_filtroDesde != null) {
          itemsFiltrados = itemsFiltrados
              .where((i) => i.fecha.isAfter(
                  _filtroDesde!.subtract(const Duration(days: 1))))
              .toList();
        }
        if (_filtroHasta != null) {
          itemsFiltrados = itemsFiltrados
              .where((i) => i.fecha.isBefore(
                  _filtroHasta!.add(const Duration(days: 1))))
              .toList();
        }

        // Ordenar por número (más reciente arriba) dentro de cada tipo,
        // pero mezclando: orden global por fecha desc y luego número desc
        itemsFiltrados.sort((a, b) {
          final f = b.fecha.compareTo(a.fecha);
          if (f != 0) return f;
          return b.numero.compareTo(a.numero);
        });

        // Totales
        final remitosCount =
            itemsFiltrados.where((i) => i.tipo == 'remito').length;
        final pagosCount =
            itemsFiltrados.where((i) => i.tipo == 'pago').length;
        final ndpCount =
            itemsFiltrados.where((i) => i.tipo == 'ndp').length;
        final totalRemitosMonto = itemsFiltrados
            .where((i) => i.tipo == 'remito')
            .fold<double>(0, (sum, i) => sum + i.monto);
        final totalPagosMonto = itemsFiltrados
            .where((i) => i.tipo == 'pago')
            .fold<double>(0, (sum, i) => sum + i.monto);

        return Column(
          children: [
            // ── Filtros ──
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  // Tipo
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _TipoChip(
                          label: 'Todos',
                          selected: _filtroTipo == 'todos',
                          onTap: () =>
                              setState(() => _filtroTipo = 'todos'),
                        ),
                        const SizedBox(width: 8),
                        _TipoChip(
                          label: 'Remitos',
                          selected: _filtroTipo == 'remito',
                          onTap: () =>
                              setState(() => _filtroTipo = 'remito'),
                        ),
                        const SizedBox(width: 8),
                        _TipoChip(
                          label: 'Pagos',
                          selected: _filtroTipo == 'pago',
                          onTap: () =>
                              setState(() => _filtroTipo = 'pago'),
                        ),
                        const SizedBox(width: 8),
                        _TipoChip(
                          label: 'Notas de Pedido',
                          selected: _filtroTipo == 'ndp',
                          onTap: () =>
                              setState(() => _filtroTipo = 'ndp'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Vendedor (A→Z)
                  DropdownButtonFormField<String>(
                    value: _filtroVendedorId,
                    decoration: const InputDecoration(
                      labelText: 'Vendedor',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Todos')),
                      ...(app.vendedores.toList()
                            ..sort((a, b) => a.nombreCompleto
                                .compareTo(b.nombreCompleto)))
                          .map((v) => DropdownMenuItem(
                              value: v.id,
                              child: Text(v.nombreCompleto,
                                  overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setState(() {
                      _filtroVendedorId = v;
                      _filtroClienteId = null;
                      _busquedaCtrl.clear();
                      _mostrarSugerencias = false;
                    }),
                  ),
                  const SizedBox(height: 8),
                  // Autocomplete cliente (campo único)
                  TextField(
                    controller: _busquedaCtrl,
                    onChanged: (v) => setState(() {
                      _filtroClienteId = null;
                      _mostrarSugerencias = v.isNotEmpty;
                    }),
                    onTapOutside: (_) => Future.delayed(
                      const Duration(milliseconds: 150),
                      () {
                        if (mounted) {
                          setState(() => _mostrarSugerencias = false);
                        }
                      },
                    ),
                    decoration: InputDecoration(
                      hintText: 'Buscar cliente...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                      suffixIcon: _busquedaCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () {
                                _busquedaCtrl.clear();
                                setState(() {
                                  _filtroClienteId = null;
                                  _mostrarSugerencias = false;
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  if (_mostrarSugerencias) Builder(builder: (_) {
                    final q = _busquedaCtrl.text.toLowerCase();
                    var baseClientes = _filtroVendedorId != null
                        ? app.clientesDeVendedor(_filtroVendedorId!)
                        : app.clientes.toList();
                    final sugerencias = (baseClientes.toList()
                          ..sort((a, b) => a.nombreRazonSocial
                              .compareTo(b.nombreRazonSocial)))
                        .where((c) => c.nombreRazonSocial
                            .toLowerCase()
                            .contains(q))
                        .toList();
                    if (sugerencias.isEmpty) {
                      return Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.card,
                          border: Border.all(color: AppTheme.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('Sin resultados',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textHint)),
                      );
                    }
                    return Container(
                      margin: const EdgeInsets.only(top: 4),
                      constraints:
                          const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        border: Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: sugerencias.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final c = sugerencias[i];
                          final vend =
                              app.vendedorPorId(c.vendedorId);
                          return InkWell(
                            onTap: () {
                              _busquedaCtrl.text =
                                  c.nombreRazonSocial;
                              setState(() {
                                _filtroClienteId = c.id;
                                _mostrarSugerencias = false;
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                        c.nombreRazonSocial,
                                        style: const TextStyle(
                                            fontSize: 14)),
                                  ),
                                  if (vend != null)
                                    Text(vend.apellido,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme
                                                .textSecondary)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  // Fechas
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  _filtroDesde ?? DateTime.now(),
                              firstDate: DateTime(2024),
                              lastDate: DateTime.now(),
                              locale: const Locale('es'),
                            );
                            if (picked != null) {
                              setState(() => _filtroDesde = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Desde',
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                              suffixIcon: _filtroDesde != null
                                  ? IconButton(
                                      icon: const Icon(Icons.close,
                                          size: 16),
                                      onPressed: () => setState(
                                          () => _filtroDesde = null),
                                    )
                                  : const Icon(Icons.calendar_today,
                                      size: 16),
                            ),
                            child: Text(
                              _filtroDesde != null
                                  ? formatFecha(_filtroDesde!)
                                  : 'Sin filtro',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: _filtroDesde != null
                                      ? AppTheme.textPrimary
                                      : AppTheme.textHint),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  _filtroHasta ?? DateTime.now(),
                              firstDate: DateTime(2024),
                              lastDate: DateTime.now(),
                              locale: const Locale('es'),
                            );
                            if (picked != null) {
                              setState(() => _filtroHasta = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: 'Hasta',
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                              suffixIcon: _filtroHasta != null
                                  ? IconButton(
                                      icon: const Icon(Icons.close,
                                          size: 16),
                                      onPressed: () => setState(
                                          () => _filtroHasta = null),
                                    )
                                  : const Icon(Icons.calendar_today,
                                      size: 16),
                            ),
                            child: Text(
                              _filtroHasta != null
                                  ? formatFecha(_filtroHasta!)
                                  : 'Sin filtro',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: _filtroHasta != null
                                      ? AppTheme.textPrimary
                                      : AppTheme.textHint),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Resumen totales ──
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
              color: AppTheme.background,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    [
                      if (remitosCount > 0) '$remitosCount remitos',
                      if (pagosCount > 0) '$pagosCount pagos',
                      if (ndpCount > 0) '$ndpCount NP',
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (remitosCount > 0)
                        Text(
                          'Ventas: ${formatPesos(totalRemitosMonto)}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500),
                        ),
                      if (pagosCount > 0)
                        Text(
                          'Pagos: ${formatPesos(totalPagosMonto)}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.success),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // ── Lista ──
            Expanded(
              child: itemsFiltrados.isEmpty
                  ? const Center(
                      child: Text('No hay movimientos',
                          style: TextStyle(
                              color: AppTheme.textSecondary)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: itemsFiltrados.length,
                      itemBuilder: (context, index) {
                        final item = itemsFiltrados[index];
                        final cliente =
                            app.clientePorId(item.clienteId);
                        final vendedor = cliente != null
                            ? app.vendedorPorId(cliente.vendedorId)
                            : null;

                        final esNdp = item.tipo == 'ndp';
                        final esPago = item.tipo == 'pago';
                        final nombreCliente = esNdp && item.clienteId.isEmpty
                            ? (item.clienteNombreLibre ?? '?')
                            : (cliente?.nombreRazonSocial ?? '?');

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                            onTap: () {
                              // Los remitos NO se editan desde el Historial.
                              if (item.tipo == 'pago' &&
                                  app.tienePermiso('editar_pago')) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PagoFormScreen(
                                        pagoInicial: item.pago),
                                  ),
                                );
                              } else if (item.ndp != null &&
                                  item.ndp!.esPendiente &&
                                  app.tienePermiso('editar_remito')) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NotaPedidoFormScreen(
                                        ndpInicial: item.ndp),
                                  ),
                                );
                              }
                            },
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: esNdp
                                  ? AppTheme.warning.withOpacity(0.15)
                                  : esPago
                                      ? AppTheme.success.withOpacity(0.12)
                                      : AppTheme.info.withOpacity(0.12),
                              child: Icon(
                                esNdp
                                    ? Icons.assignment_outlined
                                    : esPago
                                        ? Icons.payments
                                        : Icons.receipt_long,
                                size: 18,
                                color: esNdp
                                    ? AppTheme.warning
                                    : esPago
                                        ? AppTheme.success
                                        : AppTheme.info,
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  esNdp
                                      ? item.ndp!.numeroFormateado
                                      : esPago
                                          ? item.pago!.numeroFormateado
                                          : item.remito!.numeroFormateado,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                ),
                                const SizedBox(width: 6),
                                if (esNdp)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppTheme.info.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text('NP',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: AppTheme.info,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    nombreCliente,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${formatFecha(item.fecha)} · ${vendedor?.nombreCompleto ?? ""}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textSecondary),
                                ),
                                if (esPago && item.pago?.registradoPor != null)
                                  Text(
                                    'Registrado por ${item.pago!.registradoPor}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppTheme.textSecondary,
                                    ),
                                  ),
                                if (esNdp && item.ndp != null)
                                  Text(
                                    item.ndp!.esConfirmado
                                        ? 'Confirmada'
                                        : item.ndp!.esRechazado
                                            ? 'Rechazada'
                                            : 'Pendiente',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: item.ndp!.esConfirmado
                                          ? AppTheme.success
                                          : item.ndp!.esRechazado
                                              ? AppTheme.danger
                                              : AppTheme.warning,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formatPesos(item.monto),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: esPago
                                        ? AppTheme.success
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                                if (esPago) ...[
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.picture_as_pdf,
                                        size: 18,
                                        color: AppTheme.primary),
                                    onPressed: () => _descargarRecibo(
                                        context, app, item.pago!),
                                    tooltip: 'Descargar recibo',
                                  ),
                                ],
                                if (esNdp && item.ndp != null) ...[
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(
                                        Icons.picture_as_pdf,
                                        size: 18,
                                        color: AppTheme.primary),
                                    onPressed: () =>
                                        _descargarNdpPdf(context, app, item.ndp!),
                                    tooltip: 'Descargar PDF',
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _descargarNdpPdf(
      BuildContext context, AppProvider app, NotaPedido ndp) async {
    final clienteNombre = ndp.clienteId != null
        ? (app.clientePorId(ndp.clienteId!)?.nombreRazonSocial ??
            ndp.clienteNombreLibre ??
            '?')
        : (ndp.clienteNombreLibre ?? '?');

    final cliente = ndp.clienteId != null ? app.clientePorId(ndp.clienteId!) : null;
    final vendedor = cliente != null ? app.vendedorPorId(cliente.vendedorId) : null;

    String? remitoNumero;
    if (ndp.remitoId != null) {
      try {
        final remito =
            app.remitos.firstWhere((r) => r.id == ndp.remitoId);
        remitoNumero = remito.numeroFormateado;
      } catch (_) {}
    }

    await EstadoCuentaService.generarPdfNotaPedido(
      ndp: ndp,
      clienteNombre: clienteNombre,
      remitoNumero: remitoNumero,
      vendedorNombre: vendedor?.nombreCompleto,
    );
  }

  Future<void> _descargarRecibo(
      BuildContext context, AppProvider app, Pago pago) async {
    final cliente = app.clientePorId(pago.clienteId);
    if (cliente == null) return;

    final vendedor = app.vendedorPorId(cliente.vendedorId);
    final medios = await app.getMediosDePago(pago.id);

    final remitosCliente = app.remitos
        .where((r) => r.clienteId == pago.clienteId && r.esConfirmado)
        .toList();
    // Solo los pagos ANTERIORES a este (por fecha, luego número). Así la tabla
    // de deuda y el saldo restante reflejan el estado JUSTO DESPUÉS de este
    // pago, no el actual.
    final pagosPrevios = app.pagos
        .where((p) => p.clienteId == pago.clienteId)
        .where((p) {
          final cmp = p.fecha.compareTo(pago.fecha);
          return cmp != 0 ? cmp < 0 : p.numero < pago.numero;
        })
        .toList();

    // Saldo restante = saldo guardado del pago; si es viejo y está en NULL,
    // se reconstruye (remitos confirmados − pagos hasta este inclusive).
    final totalRemitos =
        remitosCliente.fold<double>(0, (s, r) => s + r.totalPesos);
    final pagosHastaEste =
        pagosPrevios.fold<double>(0, (s, p) => s + p.montoTotal) +
            pago.montoTotal;
    final saldoRestante = pago.saldoNuevo ?? (totalRemitos - pagosHastaEste);
    final saldoAnterior =
        pago.saldoAnterior ?? (saldoRestante + pago.montoTotal);

    await ReciboService.generarYCompartirRecibo(
      pago: pago,
      medios: medios,
      cliente: cliente,
      vendedor: vendedor,
      saldoAnterior: saldoAnterior,
      saldoRestante: saldoRestante,
      remitosCliente: remitosCliente,
      pagosCliente: pagosPrevios,
    );
  }
}

class _HistorialItem {
  final String tipo; // 'remito', 'pago', 'ndp'
  final Remito? remito;
  final Pago? pago;
  final NotaPedido? ndp;
  final DateTime fecha;
  final int numero;
  final String clienteId;
  final String? clienteNombreLibre;
  final double monto;

  _HistorialItem({
    required this.tipo,
    this.remito,
    this.pago,
    this.ndp,
    required this.fecha,
    required this.numero,
    required this.clienteId,
    this.clienteNombreLibre,
    required this.monto,
  });
}

class _TipoChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TipoChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withOpacity(0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : AppTheme.textHint.withOpacity(0.3),
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: selected
                ? AppTheme.primary
                : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── Widget auxiliar _StatColumn usado en _GananciasTab ──
class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _StatColumn({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color ?? AppTheme.textPrimary,
            )),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// TAB 4: DIRECTORIO DE CLIENTES CON UBICACIÓN
// ═══════════════════════════════════════════
class _DirectorioTab extends StatefulWidget {
  const _DirectorioTab();

  @override
  State<_DirectorioTab> createState() => _DirectorioTabState();
}

class _DirectorioTabState extends State<_DirectorioTab> {
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';
  String? _filtroVendedorId;

  // Ruta de cobranza: 'deben' = todos los que deben, 'vencidos' = solo vencidos
  String _modoRuta = 'deben';
  bool _generandoRuta = false;

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        final clientes = app.clientes.toList()
          ..sort((a, b) => a.nombreRazonSocial
              .toLowerCase()
              .compareTo(b.nombreRazonSocial.toLowerCase()));

        var clientesFiltrados = _filtroVendedorId != null
            ? clientes.where((c) => c.vendedorId == _filtroVendedorId).toList()
            : clientes;
        if (_busqueda.isNotEmpty) {
          clientesFiltrados = clientesFiltrados
              .where((c) => c.nombreRazonSocial
                  .toLowerCase()
                  .contains(_busqueda.toLowerCase()))
              .toList();
        }

        if (clientes.isEmpty) {
          return const Center(
            child: Text('No hay clientes cargados',
                style: TextStyle(color: AppTheme.textSecondary)),
          );
        }

        return Column(
          children: [
            _buildRutaCobranza(context, app),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _busquedaCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar cliente...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _busqueda.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() {
                            _busquedaCtrl.clear();
                            _busqueda = '';
                          }),
                        )
                      : null,
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                ),
                onChanged: (v) => setState(() => _busqueda = v),
              ),
            ),
            if (app.vendedores.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: DropdownButtonFormField<String?>(
                  value: _filtroVendedorId,
                  decoration: InputDecoration(
                    labelText: 'Vendedor',
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ...app.vendedores.map((v) => DropdownMenuItem(
                          value: v.id,
                          child: Text(v.nombreCompleto),
                        )),
                  ],
                  onChanged: (v) => setState(() => _filtroVendedorId = v),
                ),
              ),
            Expanded(
              child: clientesFiltrados.isEmpty
                  ? const Center(
                      child: Text('Sin resultados',
                          style:
                              TextStyle(color: AppTheme.textSecondary)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: clientesFiltrados.length,
                      itemBuilder: (context, index) {
                        final c = clientesFiltrados[index];
            final vendedor = app.vendedorPorId(c.vendedorId);
            final tieneUbicacion =
                c.ubicacion.isNotEmpty || c.ubicacionUrl.isNotEmpty;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                              if (vendedor != null)
                                Text(
                                  'Vendedor: ${vendedor.nombreCompleto}',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color:
                                          AppTheme.textSecondary),
                                ),
                            ],
                          ),
                        ),
                        if (c.ubicacionUrl.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.map,
                                color: AppTheme.info, size: 22),
                            onPressed: () =>
                                _abrirMaps(c.ubicacionUrl),
                            tooltip: 'Abrir en Google Maps',
                          ),
                      ],
                    ),
                    if (c.telefono.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.phone_outlined,
                              size: 14, color: AppTheme.textHint),
                          const SizedBox(width: 6),
                          Text(c.telefono,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary)),
                        ],
                      ),
                    ],
                    if (c.ubicacion.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined,
                              size: 14, color: AppTheme.textHint),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(c.ubicacion,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color:
                                        AppTheme.textSecondary),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                    if (c.ubicacionUrl.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => _abrirMaps(c.ubicacionUrl),
                        child: Row(
                          children: [
                            const Icon(Icons.open_in_new,
                                size: 14, color: AppTheme.info),
                            const SizedBox(width: 6),
                            const Text('Ver en Google Maps',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.info,
                                    decoration:
                                        TextDecoration.underline)),
                          ],
                        ),
                      ),
                    ],
                    if (!tieneUbicacion) ...[
                      const SizedBox(height: 6),
                      const Text('Sin ubicación cargada',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textHint,
                              fontStyle: FontStyle.italic)),
                    ],
                  ],
                ),
              ),
            );
          },
                    ),
            ),
          ],
        );
      },
    );
  }

  // ── Ruta de cobranza ─────────────────────────────────────
  Widget _buildRutaCobranza(BuildContext context, AppProvider app) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: AppTheme.info.withOpacity(0.06),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.route, size: 20, color: AppTheme.info),
                SizedBox(width: 8),
                Text('Ruta de cobranza',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Arma la ruta hacia los clientes que deben, ordenada por cercanía a tu ubicación.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _modoRuta,
                    decoration: InputDecoration(
                      labelText: 'Incluir',
                      isDense: true,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'deben',
                          child: Text('Clientes que deben')),
                      DropdownMenuItem(
                          value: 'vencidos',
                          child: Text('Solo remitos vencidos')),
                    ],
                    onChanged: _generandoRuta
                        ? null
                        : (v) => setState(() => _modoRuta = v ?? 'deben'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed:
                        _generandoRuta ? null : () => _armarRuta(context, app),
                    icon: _generandoRuta
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.directions, size: 18),
                    label: Text(_generandoRuta ? 'Armando...' : 'Armar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Devuelve los clientes deudores según el modo elegido, respetando el
  /// filtro de vendedor activo.
  List<Cliente> _clientesParaRuta(AppProvider app) {
    List<Cliente> base;
    if (_modoRuta == 'vencidos') {
      base = app
          .clientesConSaldoVencido()
          .map((m) => m['cliente'] as Cliente)
          .toList();
    } else {
      base = app.clientes.where((c) => app.getSaldoCliente(c.id) > 0).toList();
    }
    if (_filtroVendedorId != null) {
      base = base.where((c) => c.vendedorId == _filtroVendedorId).toList();
    }
    return base;
  }

  Future<void> _armarRuta(BuildContext context, AppProvider app) async {
    final deudores = _clientesParaRuta(app);

    // Solo los que tienen alguna ubicación cargada
    final conUbicacion = deudores
        .where((c) =>
            c.ubicacionUrl.trim().isNotEmpty || c.ubicacion.trim().isNotEmpty)
        .toList();
    final sinUbicacion = deudores.length - conUbicacion.length;

    if (conUbicacion.isEmpty) {
      if (!mounted) return;
      final msg = deudores.isEmpty
          ? 'No hay clientes que deban en este filtro.'
          : 'Ninguno de los clientes deudores tiene ubicación cargada.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    setState(() => _generandoRuta = true);

    // Pedir ubicación actual (puede tardar/negarse)
    final origen = await RutaCobranzaService.ubicacionActual();

    final paradas = conUbicacion
        .map((c) => ParadaRuta(c, RutaCobranzaService.coordsDeCliente(c)))
        .toList();
    final ordenadas =
        RutaCobranzaService.ordenarPorCercania(paradas, origen);

    if (!mounted) return;
    setState(() => _generandoRuta = false);

    _mostrarSheetRuta(context, ordenadas, origen, sinUbicacion);
  }

  void _mostrarSheetRuta(
    BuildContext context,
    List<ParadaRuta> paradas,
    Coord? origen,
    int sinUbicacion,
  ) {
    final url = RutaCobranzaService.construirUrl(paradas, origen);
    final hayCoords = paradas.any((p) => p.tieneCoord);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (ctx, scrollCtrl) {
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textHint.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      const Icon(Icons.route,
                          size: 20, color: AppTheme.info),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${paradas.length} parada${paradas.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      origen != null
                          ? (hayCoords
                              ? 'Ordenadas por cercanía a tu ubicación.'
                              : 'Sin coordenadas: reordená las paradas en Google Maps.')
                          : 'Sin tu ubicación: reordená las paradas en Google Maps.',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ),
                ),
                if (sinUbicacion > 0)
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '$sinUbicacion cliente${sinUbicacion == 1 ? '' : 's'} sin ubicación quedó${sinUbicacion == 1 ? '' : 'aron'} fuera de la ruta.',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.warning),
                      ),
                    ),
                  ),
                if (paradas.length > 10)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Son muchas paradas: Google Maps puede mostrar solo las primeras. Conviene armar la ruta por vendedor.',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.warning),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    itemCount: paradas.length,
                    itemBuilder: (ctx, i) {
                      final p = paradas[i];
                      final dir = p.cliente.ubicacion.trim();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: p.tieneCoord
                              ? AppTheme.info
                              : AppTheme.textHint,
                          child: Text('${i + 1}',
                              style: const TextStyle(
                                  fontSize: 13, color: Colors.white)),
                        ),
                        title: Text(p.cliente.nombreRazonSocial,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          dir.isNotEmpty
                              ? dir
                              : (p.tieneCoord
                                  ? 'Ubicación por link de Maps'
                                  : 'Sin dirección'),
                          style: const TextStyle(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _abrirMaps(url);
                        },
                        icon: const Icon(Icons.map),
                        label: const Text('Abrir en Google Maps'),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _abrirMaps(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ═══════════════════════════════════════════
// TAB 6: COMISIONES
// ═══════════════════════════════════════════
class _ComisionesTab extends StatefulWidget {
  const _ComisionesTab();

  @override
  State<_ComisionesTab> createState() => _ComisionesTabState();
}

class _ComisionesTabState extends State<_ComisionesTab> {
  String? _vendedorId;
  DateTime _desde = _inicioMesActual();
  DateTime _hasta = DateTime.now();
  final _pctCtrl = TextEditingController();

  static DateTime _inicioMesActual() {
    final hoy = DateTime.now();
    return DateTime(hoy.year, hoy.month, 1);
  }

  static DateTime _inicioSemanaActual() {
    final hoy = DateTime.now();
    final lunes = hoy.subtract(Duration(days: hoy.weekday - 1));
    return DateTime(lunes.year, lunes.month, lunes.day);
  }

  @override
  void dispose() {
    _pctCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        final desdeNorm = DateTime(_desde.year, _desde.month, _desde.day);
        final hastaNorm =
            DateTime(_hasta.year, _hasta.month, _hasta.day, 23, 59, 59);

        List<Remito> remitosVendedor = [];
        if (_vendedorId != null) {
          final clienteIds = app
              .clientesDeVendedor(_vendedorId!)
              .map((c) => c.id)
              .toSet();
          remitosVendedor = app.remitosConfirmados
              .where((r) =>
                  clienteIds.contains(r.clienteId) &&
                  !r.fecha.isBefore(desdeNorm) &&
                  !r.fecha.isAfter(hastaNorm))
              .toList();
        }

        double kgNovillo = 0;
        double kgCerdo = 0;
        double totalVentas = 0;
        for (final r in remitosVendedor) {
          totalVentas += r.totalPesos;
          for (final item in app.itemsDeRemito(r.id)) {
            if (item.tipoCarne.toLowerCase() == 'novillo') {
              kgNovillo += item.kgTotal;
            } else {
              kgCerdo += item.kgTotal;
            }
          }
        }

        final pct =
            double.tryParse(_pctCtrl.text.replaceAll(',', '.')) ?? 0;
        final comision = totalVentas * pct / 100;
        final vendedor =
            _vendedorId != null ? app.vendedorPorId(_vendedorId!) : null;

        final remitosOrdenados = [...remitosVendedor]
          ..sort((a, b) => b.fecha.compareTo(a.fecha));

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Filtros ──
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _vendedorId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Vendedor',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                      hint: const Text('Seleccioná un vendedor',
                          style: TextStyle(fontSize: 13)),
                      items: app.vendedores
                          .map((v) => DropdownMenuItem(
                                value: v.id,
                                child: Text(v.nombreCompleto,
                                    style:
                                        const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _vendedorId = val),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _DateField(
                            label: 'Desde',
                            value: _desde,
                            onChanged: (d) =>
                                setState(() => _desde = d),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DateField(
                            label: 'Hasta',
                            value: _hasta,
                            onChanged: (d) =>
                                setState(() => _hasta = d),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _AtajoChip(
                          label: 'Esta semana',
                          onTap: () => setState(() {
                            _desde = _inicioSemanaActual();
                            _hasta = DateTime.now();
                          }),
                        ),
                        const SizedBox(width: 6),
                        _AtajoChip(
                          label: 'Sem. anterior',
                          onTap: () => setState(() {
                            final lunes = _inicioSemanaActual();
                            _desde = lunes
                                .subtract(const Duration(days: 7));
                            _hasta = lunes
                                .subtract(const Duration(days: 1));
                          }),
                        ),
                        const SizedBox(width: 6),
                        _AtajoChip(
                          label: 'Mes actual',
                          onTap: () => setState(() {
                            _desde = _inicioMesActual();
                            _hasta = DateTime.now();
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            if (_vendedorId == null)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'Seleccioná un vendedor para calcular comisiones',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary),
                    ),
                  ),
                ),
              )
            else ...[
              // ── Resumen de ventas ──
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vendedor?.nombreCompleto ?? '',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                      Text(
                        '${formatFecha(_desde)} al ${formatFecha(_hasta)}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _StatColumn(
                              label: 'Remitos',
                              value:
                                  '${remitosVendedor.length}',
                            ),
                          ),
                          Expanded(
                            child: _StatColumn(
                              label: 'Kg Novillo',
                              value: formatKg(kgNovillo),
                            ),
                          ),
                          Expanded(
                            child: _StatColumn(
                              label: 'Kg Cerdo',
                              value: formatKg(kgCerdo),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total ventas',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary)),
                          Text(
                            formatPesos(totalVentas),
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Cálculo de comisión ──
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Comisión',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: TextFormField(
                              controller: _pctCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                labelText: '% comisión',
                                suffixText: '%',
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              children: [
                                const Text('Monto a pagar',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color:
                                            AppTheme.textSecondary)),
                                Text(
                                  formatPesos(comision),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: remitosVendedor.isEmpty
                              ? null
                              : () => _generarPdf(
                                    context,
                                    app,
                                    vendedor!,
                                    remitosOrdenados,
                                    kgNovillo,
                                    kgCerdo,
                                    totalVentas,
                                    pct,
                                    comision,
                                  ),
                          icon: const Icon(Icons.picture_as_pdf,
                              size: 18),
                          label: const Text('Emitir PDF de comisión'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Detalle de remitos ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Detalle de remitos',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary)),
                  Text('${remitosVendedor.length} en total',
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textHint)),
                ],
              ),
              const SizedBox(height: 8),
              if (remitosOrdenados.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: const [
                        Icon(Icons.receipt_long_outlined,
                            size: 40, color: AppTheme.textHint),
                        SizedBox(height: 8),
                        Text('Sin remitos en el período',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                )
              else
                ...remitosOrdenados.map((r) {
                  final cliente = app.clientes.firstWhere(
                    (c) => c.id == r.clienteId,
                    orElse: () => Cliente(
                        nombreRazonSocial: '-',
                        telefono: '',
                        vendedorId: '',
                        plazoPagoDias: 0),
                  );
                  return Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      dense: true,
                      title: Text(
                          '${r.numeroFormateado} · ${cliente.nombreRazonSocial}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      subtitle: Text(formatFecha(r.fecha),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary)),
                      trailing: Text(formatPesos(r.totalPesos),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                    ),
                  );
                }),
            ],
            const SizedBox(height: 40),
          ],
        );
      },
    );
  }

  Future<void> _generarPdf(
    BuildContext context,
    AppProvider app,
    Vendedor vendedor,
    List<Remito> remitos,
    double kgNovillo,
    double kgCerdo,
    double totalVentas,
    double pct,
    double comision,
  ) async {
    final clientesMap = {for (final c in app.clientes) c.id: c};
    await EstadoCuentaService.generarPdfComision(
      vendedor: vendedor,
      desde: _desde,
      hasta: _hasta,
      remitos: remitos,
      clientesMap: clientesMap,
      kgNovillo: kgNovillo,
      kgCerdo: kgCerdo,
      totalVentas: totalVentas,
      porcentaje: pct,
      comision: comision,
    );
  }
}

// ═══════════════════════════════════════════
// TAB 7: ELIMINADOS
// ═══════════════════════════════════════════
class _EliminadosTab extends StatelessWidget {
  const _EliminadosTab();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Pagos'),
              Tab(text: 'Remitos'),
              Tab(text: 'Notas de Pedido'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _PagosEliminadosList(),
                _RemitosEliminadosList(),
                _NotasPedidoEliminadasList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PagosEliminadosList extends StatelessWidget {
  const _PagosEliminadosList();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        final lista = app.pagosEliminados;
        if (lista.isEmpty) {
          return const Center(
            child: Text('No hay pagos eliminados',
                style: TextStyle(color: AppTheme.textHint)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: lista.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final pe = lista[i];
            final cliente = app.clientePorId(pe.clienteId);
            final nombreCliente =
                cliente?.nombreRazonSocial ?? '(cliente eliminado)';
            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFFEEEEEE))),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Encabezado: número + monto
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            pe.numeroFormateado,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppTheme.danger,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          formatPesos(pe.montoTotal),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const Spacer(),
                        Text(
                          formatFecha(pe.eliminadoEn),
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textHint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Cliente y fecha original
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 14, color: AppTheme.textHint),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(nombreCliente,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        Text(
                          'Fecha pago: ${formatFecha(pe.fecha)}',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textHint),
                        ),
                      ],
                    ),
                    // Medios de pago
                    if (pe.medios.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: pe.medios.map((m) {
                          final label = _medioLabel(m['medio'] as String? ?? '');
                          final monto =
                              (m['monto'] as num?)?.toDouble() ?? 0.0;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(5),
                              border:
                                  Border.all(color: const Color(0xFFDDDDDD)),
                            ),
                            child: Text(
                              '$label ${formatPesos(monto)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    // Quién eliminó
                    if (pe.eliminadoPor != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.delete_outline,
                              size: 13, color: AppTheme.textHint),
                          const SizedBox(width: 4),
                          Text(
                            'Eliminado por ${pe.eliminadoPor}',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textHint),
                          ),
                        ],
                      ),
                    ],
                    // Observación
                    if (pe.observacion != null &&
                        pe.observacion!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFDE7),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFFEE58)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.comment_outlined,
                                size: 13, color: Color(0xFFF57F17)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                pe.observacion!,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _medioLabel(String medio) {
    switch (medio) {
      case 'efectivo':
        return 'Efectivo';
      case 'transferencia':
        return 'Transferencia';
      case 'cheque':
        return 'Cheque';
      default:
        return medio;
    }
  }
}

class _RemitosEliminadosList extends StatelessWidget {
  const _RemitosEliminadosList();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        final lista = app.remitosEliminados;
        if (lista.isEmpty) {
          return const Center(
            child: Text('No hay remitos eliminados',
                style: TextStyle(color: AppTheme.textHint)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: lista.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final re = lista[i];
            final cliente = app.clientePorId(re.clienteId);
            final nombreCliente =
                cliente?.nombreRazonSocial ?? '(cliente eliminado)';
            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFFEEEEEE))),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            re.numeroFormateado,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppTheme.danger,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          formatPesos(re.totalPesos),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const Spacer(),
                        Text(
                          formatFecha(re.eliminadoEn),
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textHint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 14, color: AppTheme.textHint),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(nombreCliente,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        Text(
                          'Fecha remito: ${formatFecha(re.fecha)}',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textHint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatKg(re.totalKg)} kg',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textHint),
                    ),
                    if (re.eliminadoPor != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.delete_outline,
                              size: 13, color: AppTheme.textHint),
                          const SizedBox(width: 4),
                          Text(
                            'Eliminado por ${re.eliminadoPor}',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textHint),
                          ),
                        ],
                      ),
                    ],
                    if (re.observacion != null &&
                        re.observacion!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _observacionBox(re.observacion!),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// Caja amarilla reutilizable para mostrar la observación de una baja
Widget _observacionBox(String texto) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFDE7),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0xFFFFEE58)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.comment_outlined,
            size: 13, color: Color(0xFFF57F17)),
        const SizedBox(width: 5),
        Expanded(
          child: Text(texto, style: const TextStyle(fontSize: 12)),
        ),
      ],
    ),
  );
}

class _NotasPedidoEliminadasList extends StatelessWidget {
  const _NotasPedidoEliminadasList();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        final lista = app.notasPedidoEliminadas;
        if (lista.isEmpty) {
          return const Center(
            child: Text('No hay notas de pedido eliminadas',
                style: TextStyle(color: AppTheme.textHint)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: lista.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final ne = lista[i];
            final nombreCliente = ne.clienteNombre ?? '(sin cliente)';
            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFFEEEEEE))),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ne.numeroFormateado,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppTheme.danger,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          formatPesos(ne.totalPesos),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const Spacer(),
                        Text(
                          formatFecha(ne.eliminadoEn),
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textHint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.person_outline,
                            size: 14, color: AppTheme.textHint),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(nombreCliente,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        Text(
                          'Fecha: ${formatFecha(ne.fecha)}',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.textHint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatKg(ne.totalKg)} kg',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textHint),
                    ),
                    if (ne.eliminadoPor != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.delete_outline,
                              size: 13, color: AppTheme.textHint),
                          const SizedBox(width: 4),
                          Text(
                            'Eliminado por ${ne.eliminadoPor}',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textHint),
                          ),
                        ],
                      ),
                    ],
                    if (ne.observacion != null &&
                        ne.observacion!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _observacionBox(ne.observacion!),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ═══════════════════════════════════════════
// TAB 8: REPORTE POR CLIENTE
// ═══════════════════════════════════════════
class _ReporteTab extends StatefulWidget {
  const _ReporteTab();

  @override
  State<_ReporteTab> createState() => _ReporteTabState();
}

class _ReporteTabState extends State<_ReporteTab> {
  String? _clienteId;
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        // Selector de cliente
        final clientesOrdenados = [...app.clientes]
          ..sort((a, b) => a.nombreRazonSocial
              .toLowerCase()
              .compareTo(b.nombreRazonSocial.toLowerCase()));
        final clientesFiltrados = _busqueda.isEmpty
            ? clientesOrdenados
            : clientesOrdenados
                .where((c) => c.nombreRazonSocial
                    .toLowerCase()
                    .contains(_busqueda.toLowerCase()))
                .toList();

        Widget body;
        if (_clienteId == null) {
          body = const Center(
            child: Text('Seleccioná un cliente para ver el reporte',
                style: TextStyle(color: AppTheme.textHint)),
          );
        } else {
          final cliente = app.clientePorId(_clienteId!);
          if (cliente == null) {
            body = const Center(child: Text('Cliente no encontrado'));
          } else {
            body = _buildReporte(app, cliente);
          }
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar cliente',
                      prefixIcon: Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _busqueda = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: _clienteId,
                    decoration: const InputDecoration(
                      labelText: 'Cliente',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('— Seleccionar —')),
                      ...clientesFiltrados.map((c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.nombreRazonSocial,
                                overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (v) => setState(() => _clienteId = v),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: body),
          ],
        );
      },
    );
  }

  Widget _buildReporte(AppProvider app, Cliente cliente) {
    final hoy = DateTime.now();
    final plazo = cliente.plazoPagoDias;

    // Remitos confirmados del cliente, ordenados cronológicamente
    final remitos = app.remitosConfirmados
        .where((r) => r.clienteId == cliente.id)
        .toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));

    // Pagos del cliente, ordenados cronológicamente
    final pagos = app.pagos
        .where((p) => p.clienteId == cliente.id)
        .toList()
      ..sort((a, b) => a.fecha.compareTo(b.fecha));

    // Construir lista unificada de movimientos
    final movimientos = <_Movimiento>[];
    for (final r in remitos) {
      movimientos.add(_Movimiento(
        fecha: r.fecha,
        id: r.numeroFormateado,
        esRemito: true,
        monto: r.totalPesos,
        remitoFecha: r.fecha,
        remitoId: r.id,
      ));
    }
    for (final p in pagos) {
      movimientos.add(_Movimiento(
        fecha: p.fecha,
        id: p.numeroFormateado,
        esRemito: false,
        monto: p.montoTotal,
      ));
    }
    movimientos.sort((a, b) {
      final cmp = a.fecha.compareTo(b.fecha);
      if (cmp != 0) return cmp;
      // remitos antes que pagos del mismo día
      if (a.esRemito && !b.esRemito) return -1;
      if (!a.esRemito && b.esRemito) return 1;
      return 0;
    });

    // Calcular deuda pendiente por remito (FIFO) para marcar vencidos
    final deudaRemito = <String, double>{};
    for (final r in remitos) {
      deudaRemito[r.id] = r.totalPesos;
    }
    double pagoRestante =
        pagos.fold(0.0, (sum, p) => sum + p.montoTotal);
    for (final r in remitos) {
      if (pagoRestante <= 0) break;
      final deuda = deudaRemito[r.id]!;
      if (pagoRestante >= deuda) {
        pagoRestante -= deuda;
        deudaRemito[r.id] = 0;
      } else {
        deudaRemito[r.id] = deuda - pagoRestante;
        pagoRestante = 0;
      }
    }

    final saldo = app.getSaldoCliente(cliente.id);

    if (movimientos.isEmpty) {
      return const Center(
        child: Text('Sin movimientos para este cliente',
            style: TextStyle(color: AppTheme.textHint)),
      );
    }

    final vendedor = app.vendedorPorId(cliente.vendedorId);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Botón exportar PDF
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => EstadoCuentaService.generarReporteCliente(
                cliente: cliente,
                vendedor: vendedor,
                remitos: remitos,
                pagos: pagos,
                saldoTotal: saldo,
              ),
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('Exportar PDF'),
            ),
          ),
          const SizedBox(height: 8),
          // Leyenda de colores
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _Leyenda(
                  color: Color(0xFFB71C1C),
                  texto: 'Remito · suma deuda (+)',
                ),
                _Leyenda(
                  color: Color(0xFF2E7D32),
                  texto: 'Pago · resta deuda (−)',
                ),
              ],
            ),
          ),
          // Tabla
          Table(
            border: TableBorder.all(color: const Color(0xFFE0E0E0), width: 1),
            columnWidths: const {
              0: FixedColumnWidth(78),   // Fecha
              1: FixedColumnWidth(60),   // ID
              2: FlexColumnWidth(1),     // Monto
              3: FixedColumnWidth(84),   // Estado
              4: FlexColumnWidth(1),     // Saldo acum.
            },
            children: [
              // Header
              TableRow(
                decoration:
                    const BoxDecoration(color: Color(0xFFF5F5F5)),
                children: const [
                  _TH('Fecha'),
                  _TH('ID'),
                  _TH('Monto'),
                  _TH('Estado'),
                  _TH('Saldo acum.'),
                ],
              ),
              // Filas con saldo acumulado
              ...() {
                double saldoAcum = 0;
                return movimientos.map((mov) {
                  final esRemito = mov.esRemito;
                  saldoAcum += esRemito ? mov.monto : -mov.monto;

                  final color =
                      esRemito ? const Color(0xFFB71C1C) : const Color(0xFF2E7D32);
                  final montoStr =
                      '${esRemito ? '+' : '−'}${formatPesos(mov.monto)}';
                  final saldoColor = saldoAcum > 0
                      ? const Color(0xFFB71C1C)
                      : const Color(0xFF2E7D32);

                  String estadoStr = '';
                  Color estadoColor = Colors.transparent;
                  Color estadoFg = Colors.black;

                  if (esRemito) {
                    final deudaPend = deudaRemito[mov.remitoId] ?? 0;
                    if (deudaPend <= 0) {
                      estadoStr = 'Pagado';
                      estadoColor = const Color(0xFFE8F5E9);
                      estadoFg = const Color(0xFF2E7D32);
                    } else {
                      final vencimiento =
                          mov.remitoFecha!.add(Duration(days: plazo));
                      final diasVenc =
                          hoy.difference(vencimiento).inDays;
                      if (diasVenc > 0) {
                        estadoStr = 'Vencido $diasVenc d.';
                        estadoColor = const Color(0xFFFFEBEE);
                        estadoFg = const Color(0xFFB71C1C);
                      } else if (diasVenc >= -3) {
                        estadoStr = 'Por vencer';
                        estadoColor = const Color(0xFFFFF8E1);
                        estadoFg = const Color(0xFFF57F17);
                      } else {
                        estadoStr = 'Al día';
                        estadoColor = const Color(0xFFE8F5E9);
                        estadoFg = const Color(0xFF2E7D32);
                      }
                    }
                  } else {
                    estadoStr = 'Pago';
                    estadoColor = const Color(0xFFE8F5E9);
                    estadoFg = const Color(0xFF2E7D32);
                  }

                  return TableRow(
                    children: [
                      _TD(
                        formatFecha(mov.fecha),
                        align: TextAlign.center,
                      ),
                      _TD(mov.id, align: TextAlign.center),
                      _TD(
                        montoStr,
                        color: color,
                        bold: true,
                        align: TextAlign.right,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 3),
                          decoration: BoxDecoration(
                            color: estadoColor,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            estadoStr,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 10,
                                color: estadoFg,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      _TD(
                        formatPesos(saldoAcum),
                        color: saldoColor,
                        bold: true,
                        align: TextAlign.right,
                      ),
                    ],
                );
              }).toList();
              }(),
            ],
          ),
          const SizedBox(height: 16),
          // Saldo pendiente
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: saldo > 0
                  ? const Color(0xFFFFEBEE)
                  : const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: saldo > 0
                    ? const Color(0xFFEF9A9A)
                    : const Color(0xFFA5D6A7),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Saldo pendiente',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: saldo > 0
                        ? const Color(0xFFB71C1C)
                        : const Color(0xFF2E7D32),
                  ),
                ),
                Text(
                  formatPesos(saldo),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: saldo > 0
                        ? const Color(0xFFB71C1C)
                        : const Color(0xFF2E7D32),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Modelo interno para unificar remitos y pagos
class _Movimiento {
  final DateTime fecha;
  final String id;
  final bool esRemito;
  final double monto;
  final DateTime? remitoFecha;
  final String? remitoId;

  const _Movimiento({
    required this.fecha,
    required this.id,
    required this.esRemito,
    required this.monto,
    this.remitoFecha,
    this.remitoId,
  });
}

// Item de leyenda de colores (punto + texto)
class _Leyenda extends StatelessWidget {
  final Color color;
  final String texto;
  const _Leyenda({required this.color, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          texto,
          style: const TextStyle(
              fontSize: 11, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

// Widgets auxiliares para la tabla
class _TH extends StatelessWidget {
  final String text;
  const _TH(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _TD extends StatelessWidget {
  final String text;
  final Color? color;
  final bool bold;
  final TextAlign align;

  const _TD(this.text,
      {this.color, this.bold = false, this.align = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 11,
          color: color ?? Colors.black87,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
