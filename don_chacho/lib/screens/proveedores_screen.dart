// ============================================================
// PROVEEDORES — Lista de cargas (compra de animales vivos)
// ============================================================
// Reemplaza el Excel "Proveedores-Pagos". Cada carga es una compra de
// animales a un proveedor; abajo de cada una van los pagos que se le
// fueron haciendo.
//
// OJO: esto NO tiene nada que ver con los clientes de Joaco. Acá la plata
// SALE. Los remitos, NDP y pagos de clientes son el otro circuito.
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';
import 'carga_detalle_screen.dart';
import 'carga_form_screen.dart';
import 'gestion_proveedores_screen.dart';

class ProveedoresScreen extends StatefulWidget {
  const ProveedoresScreen({super.key});

  @override
  State<ProveedoresScreen> createState() => _ProveedoresScreenState();
}

class _ProveedoresScreenState extends State<ProveedoresScreen> {
  bool _cargando = true;
  String? _filtroProveedorId; // null = todos

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos({bool forzar = false}) async {
    setState(() => _cargando = true);
    await context.read<AppProvider>().cargarProveedores(forzar: forzar);
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proveedores'),
        actions: [
          IconButton(
            tooltip: 'Gestionar proveedores',
            icon: const Icon(Icons.groups_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GestionProveedoresScreen(),
                ),
              );
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevaCarga,
        icon: const Icon(Icons.add),
        label: const Text('Nueva carga'),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Consumer<AppProvider>(
              builder: (context, app, _) {
                final cargas = _filtroProveedorId == null
                    ? app.cargas
                    : app.cargas
                        .where((c) => c.proveedorId == _filtroProveedorId)
                        .toList();

                return RefreshIndicator(
                  onRefresh: () => _cargarDatos(forzar: true),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _ResumenDeuda(app: app),
                      const SizedBox(height: 12),
                      _FiltroProveedor(
                        valor: _filtroProveedorId,
                        proveedores: app.proveedores,
                        onChanged: (v) =>
                            setState(() => _filtroProveedorId = v),
                      ),
                      const SizedBox(height: 12),
                      if (cargas.isEmpty)
                        _VacioCargas(
                          hayProveedores: app.proveedores.isNotEmpty,
                          onNuevoProveedor: _irAProveedores,
                          onNuevaCarga: _nuevaCarga,
                        )
                      else
                        ...cargas.map((c) => _CargaCard(
                              carga: c,
                              app: app,
                              onTap: () => _abrirCarga(c),
                            )),
                      const SizedBox(height: 80),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _irAProveedores() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GestionProveedoresScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _nuevaCarga() async {
    final app = context.read<AppProvider>();
    if (app.proveedoresActivos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero cargá un proveedor'),
        ),
      );
      await _irAProveedores();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CargaFormScreen()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _abrirCarga(Carga carga) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CargaDetalleScreen(cargaId: carga.id),
      ),
    );
    if (mounted) setState(() {});
  }
}

// ─────────────────────────────────────────────
// Resumen: cuánto se le debe hoy a los proveedores
// ─────────────────────────────────────────────
class _ResumenDeuda extends StatelessWidget {
  final AppProvider app;
  const _ResumenDeuda({required this.app});

  @override
  Widget build(BuildContext context) {
    final deuda = app.deudaTotalProveedores;
    final conDeuda = app.proveedores
        .where((p) => app.saldoProveedor(p.id) < 0)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: deuda > 0 ? AppTheme.dangerBg : AppTheme.successBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                color: deuda > 0 ? AppTheme.danger : AppTheme.success,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Se le debe a proveedores',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatPesos(deuda),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: deuda > 0 ? AppTheme.danger : AppTheme.success,
                    ),
                  ),
                  if (conDeuda > 0)
                    Text(
                      '$conDeuda proveedor(es) con saldo pendiente',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textHint,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Filtro por proveedor
// ─────────────────────────────────────────────
class _FiltroProveedor extends StatelessWidget {
  final String? valor;
  final List<Proveedor> proveedores;
  final ValueChanged<String?> onChanged;

  const _FiltroProveedor({
    required this.valor,
    required this.proveedores,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (proveedores.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String?>(
      value: valor,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Proveedor',
        prefixIcon: Icon(Icons.filter_list),
      ),
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Todos'),
        ),
        ...proveedores.map(
          (p) => DropdownMenuItem<String?>(
            value: p.id,
            child: Text(p.nombre),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────────────────────────
// Tarjeta de carga
// ─────────────────────────────────────────────
class _CargaCard extends StatelessWidget {
  final Carga carga;
  final AppProvider app;
  final VoidCallback onTap;

  const _CargaCard({
    required this.carga,
    required this.app,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final saldo = app.saldoDeCarga(carga);
    final pagado = app.totalPagadoCarga(carga.id);
    // Saldo negativo = falta pagar. Cero o positivo = saldada.
    final debe = saldo < -0.5;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    carga.numeroFormateado,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      app.nombreProveedor(carga.proveedorId),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!carga.tieneFaena)
                    const StatusPill(
                      text: 'Falta faena',
                      type: StatusType.warning,
                    )
                  else if (!debe)
                    const StatusPill(
                      text: 'Saldada',
                      type: StatusType.success,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${formatFecha(carga.fecha)} · ${carga.cantidadAnimales} animales · '
                '${formatKg(carga.kgVivo)} vivo',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Divider(height: 18),
              Row(
                children: [
                  _Dato(
                    label: 'A pagar',
                    valor: formatPesos(carga.totalAPagar),
                  ),
                  _Dato(
                    label: 'Pagado',
                    valor: formatPesos(pagado),
                  ),
                  _Dato(
                    label: debe ? 'Falta pagar' : 'Saldo',
                    valor: formatPesos(saldo.abs()),
                    color: debe ? AppTheme.danger : AppTheme.success,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  final String label;
  final String valor;
  final Color? color;

  const _Dato({required this.label, required this.valor, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
          ),
          const SizedBox(height: 2),
          Text(
            valor,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Estado vacío
// ─────────────────────────────────────────────
class _VacioCargas extends StatelessWidget {
  final bool hayProveedores;
  final VoidCallback onNuevoProveedor;
  final VoidCallback onNuevaCarga;

  const _VacioCargas({
    required this.hayProveedores,
    required this.onNuevoProveedor,
    required this.onNuevaCarga,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          const Icon(Icons.local_shipping_outlined,
              size: 48, color: AppTheme.textHint),
          const SizedBox(height: 12),
          Text(
            hayProveedores
                ? 'Todavía no hay cargas registradas'
                : 'Todavía no hay proveedores',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: hayProveedores ? onNuevaCarga : onNuevoProveedor,
            icon: const Icon(Icons.add),
            label: Text(
              hayProveedores ? 'Registrar primera carga' : 'Cargar proveedor',
            ),
          ),
        ],
      ),
    );
  }
}
