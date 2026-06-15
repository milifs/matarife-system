// ============================================================
// BANDEJA DE CONFIRMACIÓN
// ============================================================
// 3 tabs: Remitos pendientes, Notas de Pedido pendientes,
// y Rechazados (remitos + NDPs combinados)
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/estado_cuenta_service.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';
import 'remito_form_screen.dart';
import 'nota_pedido_form_screen.dart';

class BandejaRemitosScreen extends StatefulWidget {
  final Usuario usuarioActual;
  const BandejaRemitosScreen({super.key, required this.usuarioActual});

  @override
  State<BandejaRemitosScreen> createState() => _BandejaRemitosScreenState();
}

class _BandejaRemitosScreenState extends State<BandejaRemitosScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _procesando = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bandeja de confirmación'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textHint,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Notas de Pedido'),
            Tab(text: 'Remitos'),
            Tab(text: 'Rechazados'),
          ],
        ),
      ),
      body: Consumer<AppProvider>(
        builder: (context, app, _) {
          final remitosPendientes = app.remitos
              .where((r) => r.esPendiente)
              .toList()
            ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));

          final hoy = DateTime.now();
          final diaHoy = DateTime(hoy.year, hoy.month, hoy.day);
          final ndpsVisibles = app.notasPedido.where((n) {
            if (n.esRechazado) return false;
            if (n.esPendiente) return true;
            // confirmadas: mostrar hasta 1 día después de la confirmación
            final fechaRef = n.confirmadoEn ?? n.creadoEn;
            final diaRef =
                DateTime(fechaRef.year, fechaRef.month, fechaRef.day);
            return diaHoy.difference(diaRef).inDays <= 1;
          }).toList()
            ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));

          final remitosRechazados = app.remitos
              .where((r) => r.esRechazado)
              .toList()
            ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));

          final ndpsRechazadas = app.notasPedido
              .where((n) => n.esRechazado)
              .toList()
            ..sort((a, b) => b.creadoEn.compareTo(a.creadoEn));

          return TabBarView(
            controller: _tabCtrl,
            children: [
              _buildListaNdp(app, ndpsVisibles),
              _buildListaRemitos(app, remitosPendientes, esPendiente: true),
              _buildRechazados(app, remitosRechazados, ndpsRechazadas),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────
  // TAB 1: REMITOS PENDIENTES
  // ─────────────────────────────────────────
  Widget _buildListaRemitos(AppProvider app, List<Remito> remitos,
      {required bool esPendiente}) {
    if (remitos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 48, color: AppTheme.textHint),
            const SizedBox(height: 12),
            const Text('No hay remitos pendientes',
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: remitos.length,
      itemBuilder: (context, i) =>
          _RemitoCard(
            remito: remitos[i],
            app: app,
            esPendiente: true,
            onConfirmar: () => _confirmarRemito(remitos[i]),
            onEditar: () => _editarRemito(remitos[i]),
            onRechazar: () => _rechazarRemito(remitos[i]),
          ),
    );
  }

  // ─────────────────────────────────────────
  // TAB 2: NOTAS DE PEDIDO DEL DÍA
  // ─────────────────────────────────────────
  Widget _buildListaNdp(AppProvider app, List<NotaPedido> ndps) {
    if (ndps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment_outlined,
                size: 48, color: AppTheme.textHint),
            const SizedBox(height: 12),
            const Text('No hay notas de pedido',
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: ndps.length,
      itemBuilder: (context, i) {
        final ndp = ndps[i];
        return _NdpCard(
          ndp: ndp,
          app: app,
          onConfirmar: ndp.esPendiente ? () => _confirmarNdp(ndp) : null,
          onEditar: ndp.esPendiente ? () => _editarNdp(ndp) : null,
          onRechazar: ndp.esPendiente ? () => _rechazarNdp(ndp) : null,
          onPdf: () => _descargarPdfNdp(ndp, app),
        );
      },
    );
  }

  // ─────────────────────────────────────────
  // TAB 3: RECHAZADOS (remitos + NDPs)
  // ─────────────────────────────────────────
  Widget _buildRechazados(AppProvider app, List<Remito> remitos,
      List<NotaPedido> ndps) {
    if (remitos.isEmpty && ndps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 48, color: AppTheme.textHint),
            const SizedBox(height: 12),
            const Text('No hay rechazados',
                style: TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...remitos.map((r) => _RemitoCard(
              remito: r,
              app: app,
              esPendiente: false,
              onConfirmar: () => _confirmarRemito(r),
              onEditar: () => _editarRemito(r),
              onRechazar: null,
            )),
        ...ndps.map((n) => _NdpCard(
              ndp: n,
              app: app,
              onConfirmar: null,
              onEditar: null,
              onRechazar: null,
              onPdf: () => _descargarPdfNdp(n, app),
            )),
      ],
    );
  }

  // ─────────────────────────────────────────
  // ACCIONES — REMITO
  // ─────────────────────────────────────────

  Future<void> _confirmarRemito(Remito remito) async {
    if (_procesando) return;
    setState(() => _procesando = true);
    try {
      final app = context.read<AppProvider>();
      await app.confirmarRemito(remito.id, widget.usuarioActual.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${remito.numeroFormateado} confirmado'),
          backgroundColor: AppTheme.success,
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _rechazarRemito(Remito remito) async {
    final motivoCtrl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rechazar ${remito.numeroFormateado}'),
        content: TextField(
          controller: motivoCtrl,
          decoration: const InputDecoration(
            labelText: 'Motivo del rechazo (opcional)',
            hintText: 'Ej: datos incorrectos, precio mal cargado...',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, motivoCtrl.text),
              style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              child: const Text('Rechazar')),
        ],
      ),
    );
    if (motivo == null || !mounted) return;
    final app = context.read<AppProvider>();
    await app.rechazarRemito(remito.id, widget.usuarioActual.id,
        motivo.isNotEmpty ? motivo : null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${remito.numeroFormateado} rechazado'),
        backgroundColor: AppTheme.warning,
      ));
    }
  }

  Future<void> _editarRemito(Remito remito) async {
    await Navigator.push(context,
        MaterialPageRoute(
            builder: (_) => RemitoFormScreen(remitoInicial: remito)));
  }

  // ─────────────────────────────────────────
  // ACCIONES — NDP
  // ─────────────────────────────────────────

  Future<void> _confirmarNdp(NotaPedido ndp) async {
    if (_procesando) return;

    // Si el cliente es texto libre, pedir que elija de lista antes de confirmar
    String? clienteId = ndp.clienteId;
    if (clienteId == null) {
      clienteId = await _seleccionarClienteParaNdp(ndp);
      if (clienteId == null) return; // canceló
    }

    setState(() => _procesando = true);
    try {
      final app = context.read<AppProvider>();
      final remito = await app.confirmarNotaPedido(
          ndp, clienteId, widget.usuarioActual.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            remito != null
                ? '${ndp.numeroFormateado} confirmada → ${remito.numeroFormateado}'
                : 'Error al confirmar la nota de pedido',
          ),
          backgroundColor:
              remito != null ? AppTheme.success : AppTheme.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /// Muestra diálogo para asignar cliente de lista cuando la NDP era texto libre
  Future<String?> _seleccionarClienteParaNdp(NotaPedido ndp) async {
    final app = context.read<AppProvider>();
    String? clienteSeleccionado;
    String busqueda = '';

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          var clientes = app.clientes.toList()
            ..sort((a, b) =>
                a.nombreRazonSocial.compareTo(b.nombreRazonSocial));
          if (busqueda.isNotEmpty) {
            final q = busqueda.toLowerCase();
            clientes = clientes
                .where((c) =>
                    c.nombreRazonSocial.toLowerCase().contains(q))
                .toList();
          }
          return AlertDialog(
            title: const Text('Asignar cliente'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'La nota fue cargada con cliente: "${ndp.clienteNombreLibre}".\nAsignala a un cliente de la lista para confirmar.',
                    style: const TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Buscar',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                    onChanged: (v) =>
                        setDialogState(() => busqueda = v),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: clientes.length,
                      itemBuilder: (_, i) {
                        final c = clientes[i];
                        final sel = clienteSeleccionado == c.id;
                        return ListTile(
                          dense: true,
                          selected: sel,
                          selectedTileColor:
                              AppTheme.primary.withOpacity(0.08),
                          title: Text(c.nombreRazonSocial,
                              style: const TextStyle(fontSize: 13)),
                          trailing: sel
                              ? const Icon(Icons.check,
                                  color: AppTheme.primary)
                              : null,
                          onTap: () => setDialogState(
                              () => clienteSeleccionado = c.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancelar')),
              FilledButton(
                onPressed: clienteSeleccionado != null
                    ? () => Navigator.pop(ctx, clienteSeleccionado)
                    : null,
                child: const Text('Confirmar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _rechazarNdp(NotaPedido ndp) async {
    final motivoCtrl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Rechazar ${ndp.numeroFormateado}'),
        content: TextField(
          controller: motivoCtrl,
          decoration: const InputDecoration(
            labelText: 'Motivo del rechazo (opcional)',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, motivoCtrl.text),
              style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              child: const Text('Rechazar')),
        ],
      ),
    );
    if (motivo == null || !mounted) return;
    final app = context.read<AppProvider>();
    await app.rechazarNotaPedido(
        ndp.id, widget.usuarioActual.id, motivo.isNotEmpty ? motivo : null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${ndp.numeroFormateado} rechazada'),
        backgroundColor: AppTheme.warning,
      ));
    }
  }

  Future<void> _editarNdp(NotaPedido ndp) async {
    await Navigator.push(context,
        MaterialPageRoute(
            builder: (_) => NotaPedidoFormScreen(ndpInicial: ndp)));
  }

  Future<void> _descargarPdfNdp(NotaPedido ndp, AppProvider app) async {
    final clienteNombre = ndp.clienteId != null
        ? (app.clientePorId(ndp.clienteId!)?.nombreRazonSocial ??
            ndp.clienteNombreLibre ??
            '?')
        : (ndp.clienteNombreLibre ?? '?');

    final cliente = ndp.clienteId != null ? app.clientePorId(ndp.clienteId!) : null;
    final vendedor = cliente != null ? app.vendedorPorId(cliente.vendedorId) : null;

    String? remitoNumero;
    if (ndp.esConfirmado && ndp.remitoId != null) {
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
}

// ─────────────────────────────────────────────
// CARD DE REMITO
// ─────────────────────────────────────────────
class _RemitoCard extends StatelessWidget {
  final Remito remito;
  final AppProvider app;
  final bool esPendiente;
  final VoidCallback onConfirmar;
  final VoidCallback onEditar;
  final VoidCallback? onRechazar;

  const _RemitoCard({
    required this.remito,
    required this.app,
    required this.esPendiente,
    required this.onConfirmar,
    required this.onEditar,
    this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    final cliente = app.clientePorId(remito.clienteId);
    final vendedor =
        cliente != null ? app.vendedorPorId(cliente.vendedorId) : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(remito.numeroFormateado,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                StatusPill(
                  text: esPendiente ? 'Pendiente' : 'Rechazado',
                  type: esPendiente
                      ? StatusType.warning
                      : StatusType.danger,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${cliente?.nombreRazonSocial ?? "?"} · ${vendedor?.nombreCompleto ?? ""}',
              style: const TextStyle(fontSize: 13),
            ),
            Text(
              'Fecha: ${formatFecha(remito.fecha)} · ${formatKg(remito.totalKg)} · ${formatPesos(remito.totalPesos)}',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary),
            ),
            if (remito.esRechazado && remito.motivoRechazo != null) ...[
              const SizedBox(height: 6),
              _MotivoBox(motivo: remito.motivoRechazo!),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (onRechazar != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onRechazar,
                      icon: const Icon(Icons.close,
                          size: 18, color: AppTheme.danger),
                      label: const Text('Rechazar',
                          style: TextStyle(color: AppTheme.danger)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEditar,
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Editar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onConfirmar,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Confirmar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// CARD DE NOTA DE PEDIDO
// ─────────────────────────────────────────────
class _NdpCard extends StatelessWidget {
  final NotaPedido ndp;
  final AppProvider app;
  final VoidCallback? onConfirmar;
  final VoidCallback? onEditar;
  final VoidCallback? onRechazar;
  final VoidCallback? onPdf;

  const _NdpCard({
    required this.ndp,
    required this.app,
    this.onConfirmar,
    this.onEditar,
    this.onRechazar,
    this.onPdf,
  });

  @override
  Widget build(BuildContext context) {
    final clienteNombre = ndp.clienteId != null
        ? (app.clientePorId(ndp.clienteId!)?.nombreRazonSocial ??
            ndp.clienteNombreLibre ??
            '?')
        : (ndp.clienteNombreLibre ?? '?');

    final cliente = ndp.clienteId != null ? app.clientePorId(ndp.clienteId!) : null;
    final vendedor = cliente != null ? app.vendedorPorId(cliente.vendedorId) : null;

    final StatusType statusType;
    final String statusText;
    if (ndp.esConfirmado) {
      statusType = StatusType.success;
      statusText = 'Aprobado';
    } else if (ndp.esRechazado) {
      statusType = StatusType.danger;
      statusText = 'Rechazada';
    } else {
      statusType = StatusType.warning;
      statusText = 'Pendiente';
    }

    final bool acciones = onConfirmar != null || onEditar != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(ndp.numeroFormateado,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.info.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('NP',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.info,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                StatusPill(text: statusText, type: statusType),
              ],
            ),
            const SizedBox(height: 8),
            Text(clienteNombre,
                style: const TextStyle(fontSize: 13)),
            if (vendedor != null)
              Text('Vendedor: ${vendedor.nombreCompleto}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.textSecondary)),
            if (ndp.clienteId == null && ndp.esPendiente)
              const Text('Cliente texto libre — requiere asignación al confirmar',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.warning)),
            Text(
              'Fecha: ${formatFecha(ndp.fecha)} · ${formatKg(ndp.totalKg)} · ${formatPesos(ndp.totalPesos)}',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary),
            ),
            ...ndp.items.map((item) {
              final desc = item.descripcion.isNotEmpty
                  ? item.descripcion
                  : '—';
              return Text(
                '$desc  ·  ${formatKg(item.totalKg)}  ·  ${formatPesos(item.precioPorMedia)}/kg',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textHint),
              );
            }),
            if (ndp.esRechazado && ndp.motivoRechazo != null) ...[
              const SizedBox(height: 6),
              _MotivoBox(motivo: ndp.motivoRechazo!),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (acciones) ...[
                  if (onRechazar != null) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onRechazar,
                        icon: const Icon(Icons.close,
                            size: 18, color: AppTheme.danger),
                        label: const Text('Rechazar',
                            style: TextStyle(color: AppTheme.danger)),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onEditar,
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('Editar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onConfirmar,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Confirmar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: onPdf,
                  icon: const Icon(Icons.picture_as_pdf,
                      size: 18, color: AppTheme.primary),
                  label: const Text('PDF',
                      style: TextStyle(color: AppTheme.primary)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MotivoBox extends StatelessWidget {
  final String motivo;
  const _MotivoBox({required this.motivo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(0.05),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppTheme.danger),
          const SizedBox(width: 6),
          Expanded(
            child: Text('Motivo: $motivo',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
