// ============================================================
// FORMULARIO DE PAGO - Múltiples medios de pago
// ============================================================
// Efectivo y cheque: entran al 100%
// Transferencia: se descuenta 6.2% (5% rentas + 1.2% CyD)
// Genera recibo PDF para compartir por WhatsApp
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';
import '../services/recibo_service.dart';

class PagoFormScreen extends StatefulWidget {
  final Cliente? clienteInicial;
  final Pago? pagoInicial;

  const PagoFormScreen({
    super.key,
    this.clienteInicial,
    this.pagoInicial,
  });

  @override
  State<PagoFormScreen> createState() => _PagoFormScreenState();
}

class _PagoFormScreenState extends State<PagoFormScreen> {
  String? _clienteId;
  final TextEditingController _busquedaCtrl = TextEditingController();
  bool _mostrarSugerencias = false;
  DateTime _fechaPago = DateTime.now();
  final List<_MedioForm> _medios = [_MedioForm(medio: MedioPago.efectivo)];
  bool _guardando = false;

  bool get _esEdicion => widget.pagoInicial != null;

  double get _montoTotal =>
      _medios.fold(0, (sum, m) => sum + (m.monto ?? 0));

  double get _totalDescuentos => _medios.fold(0, (sum, m) {
        final monto = m.monto ?? 0;
        if (m.medio == MedioPago.transferencia) {
          return sum + (monto * 0.062);
        }
        return sum;
      });

  double get _netoRecibido => _montoTotal - _totalDescuentos;

  @override
  void initState() {
    super.initState();
    _clienteId = widget.clienteInicial?.id ?? widget.pagoInicial?.clienteId;
    if (widget.pagoInicial != null) {
      _fechaPago = widget.pagoInicial!.fecha;
      // Cargar medios existentes
      _cargarMediosExistentes();
    }
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarMediosExistentes() async {
    final app = context.read<AppProvider>();
    final medios = await app.getMediosDePago(widget.pagoInicial!.id);
    if (mounted && medios.isNotEmpty) {
      setState(() {
        _medios.clear();
        for (final m in medios) {
          _medios.add(_MedioForm(medio: m.medio)..monto = m.monto);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final saldoCliente =
        _clienteId != null ? app.getSaldoCliente(_clienteId!) : 0.0;
    final cliente =
        _clienteId != null ? app.clientePorId(_clienteId!) : null;
    final vendedor = cliente != null
        ? app.vendedorPorId(cliente.vendedorId)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion ? 'Ver pago' : 'Registrar pago'),
        actions: [
          if (_esEdicion && app.tienePermiso('editar_pago'))
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppTheme.danger),
              onPressed: _guardando ? null : _confirmarEliminar,
              tooltip: 'Eliminar pago',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Cliente ──
          if (widget.clienteInicial != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.clienteInicial!.nombreRazonSocial,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (!_esEdicion) ...[
            TextField(
              controller: _busquedaCtrl,
              onChanged: (v) => setState(() {
                _clienteId = null;
                _mostrarSugerencias = v.isNotEmpty;
              }),
              onTapOutside: (_) => Future.delayed(
                const Duration(milliseconds: 150),
                () { if (mounted) setState(() => _mostrarSugerencias = false); },
              ),
              decoration: InputDecoration(
                hintText: 'Buscar cliente...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                suffixIcon: _busquedaCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _busquedaCtrl.clear();
                          setState(() {
                            _clienteId = null;
                            _mostrarSugerencias = false;
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            if (_mostrarSugerencias) Builder(builder: (_) {
              final q = _busquedaCtrl.text.toLowerCase();
              final sugerencias = (app.clientes.toList()
                    ..sort((a, b) => a.nombreRazonSocial
                        .compareTo(b.nombreRazonSocial)))
                  .where((c) =>
                      c.nombreRazonSocial.toLowerCase().contains(q))
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
                          fontSize: 13, color: AppTheme.textHint)),
                );
              }
              return Container(
                margin: const EdgeInsets.only(top: 4),
                constraints: const BoxConstraints(maxHeight: 220),
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
                    final v = app.vendedorPorId(c.vendedorId);
                    return InkWell(
                      borderRadius: i == 0
                          ? const BorderRadius.vertical(
                              top: Radius.circular(10))
                          : i == sugerencias.length - 1
                              ? const BorderRadius.vertical(
                                  bottom: Radius.circular(10))
                              : BorderRadius.zero,
                      onTap: () {
                        _busquedaCtrl.text = c.nombreRazonSocial;
                        setState(() {
                          _clienteId = c.id;
                          _mostrarSugerencias = false;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(c.nombreRazonSocial,
                                  style: const TextStyle(fontSize: 14)),
                            ),
                            if (v != null)
                              Text(v.apellido,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppTheme.textSecondary)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
          ],

          if (cliente != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(cliente.nombreRazonSocial,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w500)),
                        if (vendedor != null)
                          Text('Vendedor: ${vendedor.nombreCompleto}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary)),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Saldo pendiente',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary)),
                        Text(
                          formatPesos(saldoCliente),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: saldoCliente > 0
                                ? AppTheme.danger
                                : AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          // ── Fecha de pago ──
          if (_esEdicion)
            InputDecorator(
              decoration: const InputDecoration(labelText: 'Fecha de pago'),
              child: Text(formatFecha(_fechaPago)),
            )
          else
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _fechaPago,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  locale: const Locale('es'),
                );
                if (picked != null) setState(() => _fechaPago = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Fecha de pago',
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(formatFecha(_fechaPago)),
              ),
            ),

          const SizedBox(height: 20),

          // ── Medios de pago ──
          const Text('Medios de pago',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 10),

          ..._medios.asMap().entries.map((entry) {
            final idx = entry.key;
            final m = entry.value;
            return _MedioCard(
              medioForm: m,
              canRemove: !_esEdicion && _medios.length > 1,
              onRemove: () => setState(() => _medios.removeAt(idx)),
              onChanged: () => setState(() {}),
              readOnly: _esEdicion,
            );
          }),

          if (!_esEdicion)
            OutlinedButton.icon(
              onPressed: () {
                // Elegir medio que no esté ya agregado
                final usados = _medios.map((m) => m.medio).toSet();
                MedioPago nuevo = MedioPago.efectivo;
                if (!usados.contains(MedioPago.transferencia)) {
                  nuevo = MedioPago.transferencia;
                } else if (!usados.contains(MedioPago.cheque)) {
                  nuevo = MedioPago.cheque;
                }
                setState(() => _medios.add(_MedioForm(medio: nuevo)));
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar otro medio de pago'),
            ),

          const SizedBox(height: 20),

          // ── Resumen ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ..._medios.map((m) {
                    final monto = m.monto ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_medioLabel(m.medio),
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary)),
                          Text(formatPesos(monto),
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    );
                  }),
                  if (_totalDescuentos > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Descuento transf. (6.2%)',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary)),
                        Text(
                          '-${formatPesos(_totalDescuentos)}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.danger),
                        ),
                      ],
                    ),
                  ],
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Neto recibido',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      Text(
                        formatPesos(_netoRecibido),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                  if (_clienteId != null && !_esEdicion) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Saldo restante',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textSecondary)),
                        Text(
                          formatPesos(saldoCliente - _montoTotal),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: (saldoCliente - _montoTotal) > 0
                                ? AppTheme.danger
                                : AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Botones ──
          if (!_esEdicion)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        _guardando || _clienteId == null || _montoTotal <= 0
                            ? null
                            : _guardarPago,
                    child: _guardando
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Guardar pago'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _clienteId == null || _montoTotal <= 0
                            ? null
                            : () => _guardarYCompartir(),
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Guardar + Recibo'),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _guardarPago() async {
    setState(() => _guardando = true);

    final medios = _medios
        .where((m) => (m.monto ?? 0) > 0)
        .map((m) => PagoMedio(
              pagoId: widget.pagoInicial?.id ?? '',
              medio: m.medio,
              monto: m.monto!,
            ))
        .toList();

    final pago = Pago(
      id: widget.pagoInicial?.id,
      numero: widget.pagoInicial?.numero ?? 0,
      clienteId: _clienteId!,
      fecha: _fechaPago,
      montoTotal: _montoTotal,
      netoRecibido: _netoRecibido,
    );

    if (_esEdicion) {
      await context.read<AppProvider>().actualizarPago(pago, medios);
    } else {
      await context.read<AppProvider>().agregarPago(pago, medios);
    }

    setState(() => _guardando = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_esEdicion
              ? 'Pago actualizado'
              : 'Pago registrado: ${formatPesos(_montoTotal)}'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context, pago);
    }
  }

  Future<void> _confirmarEliminar() async {
    final obsCtrl = TextEditingController();
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar pago'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                '¿Seguro que querés eliminar el pago ${widget.pagoInicial!.numeroFormateado}? Esta acción no se puede deshacer.'),
            const SizedBox(height: 14),
            TextField(
              controller: obsCtrl,
              decoration: const InputDecoration(
                labelText: 'Observación (opcional)',
                hintText: 'Ej: pago duplicado, error de carga...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) {
      obsCtrl.dispose();
      return;
    }

    final observacion =
        obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim();
    obsCtrl.dispose();

    setState(() => _guardando = true);
    final app = context.read<AppProvider>();
    await app.eliminarPago(
      widget.pagoInicial!.id,
      observacion: observacion,
      eliminadoPor: app.usuarioActual?.nombreCompleto,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pago eliminado'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _guardarYCompartir() async {
    setState(() => _guardando = true);

    final app = context.read<AppProvider>();
    final cliente = app.clientePorId(_clienteId!)!;
    final vendedor = app.vendedorPorId(cliente.vendedorId);

    final medios = _medios
        .where((m) => (m.monto ?? 0) > 0)
        .map((m) => PagoMedio(
              pagoId: '',
              medio: m.medio,
              monto: m.monto!,
            ))
        .toList();

    final pago = Pago(
      clienteId: _clienteId!,
      fecha: _fechaPago,
      montoTotal: _montoTotal,
      netoRecibido: _netoRecibido,
    );

    await app.agregarPago(pago, medios);

    // Generar y compartir recibo PDF
    final saldoAnterior = app.getSaldoCliente(_clienteId!) + _montoTotal;
    final saldoNuevo = saldoAnterior - _montoTotal;

    await ReciboService.generarYCompartirRecibo(
      pago: pago,
      medios: medios,
      cliente: cliente,
      vendedor: vendedor,
      saldoAnterior: saldoAnterior,
      saldoNuevo: saldoNuevo,
      remitosCliente: app.remitos
          .where((r) => r.clienteId == _clienteId!)
          .toList(),
      pagosCliente: app.pagos
          .where((p) => p.clienteId == _clienteId!)
          .toList(),
    );

    setState(() => _guardando = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pago guardado y recibo generado'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context, pago);
    }
  }

  String _medioLabel(MedioPago medio) {
    switch (medio) {
      case MedioPago.efectivo:
        return 'Efectivo';
      case MedioPago.transferencia:
        return 'Transferencia';
      case MedioPago.cheque:
        return 'Cheque';
    }
  }
}

// ── Modelo temporal para el formulario ──
class _MedioForm {
  MedioPago medio;
  double? monto;

  _MedioForm({required this.medio, this.monto});
}

// ── Card de medio de pago individual ──
class _MedioCard extends StatelessWidget {
  final _MedioForm medioForm;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final bool readOnly;

  const _MedioCard({
    required this.medioForm,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final esTransferencia = medioForm.medio == MedioPago.transferencia;
    final monto = medioForm.monto ?? 0;
    final descuento = esTransferencia ? monto * 0.062 : 0.0;
    final neto = monto - descuento;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Header con tipo y badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    DropdownButton<MedioPago>(
                      value: medioForm.medio,
                      underline: const SizedBox(),
                      isDense: true,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textPrimary),
                      items: MedioPago.values
                          .map((m) => DropdownMenuItem(
                                value: m,
                                child: Text(_medioLabel(m)),
                              ))
                          .toList(),
                      onChanged: readOnly
                          ? null
                          : (v) {
                              if (v != null) {
                                medioForm.medio = v;
                                onChanged();
                              }
                            },
                    ),
                    const SizedBox(width: 8),
                    if (esTransferencia)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.warningBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('-6.2%',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.warning)),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.successBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Sin descuento',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.success)),
                      ),
                  ],
                ),
                if (canRemove)
                  GestureDetector(
                    onTap: onRemove,
                    child: const Text('Quitar',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.danger)),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Monto y neto
            Row(
              children: [
                Expanded(
                  child: readOnly
                      ? InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Monto',
                            prefixText: '\$ ',
                            isDense: true,
                          ),
                          child: Text(medioForm.monto != null
                              ? medioForm.monto!.toStringAsFixed(0)
                              : ''),
                        )
                      : TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Monto',
                            prefixText: '\$ ',
                            isDense: true,
                          ),
                          onChanged: (v) {
                            medioForm.monto = double.tryParse(v);
                            onChanged();
                          },
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Neto recibido',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary)),
                        Text(
                          formatPesos(neto),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: esTransferencia
                                ? AppTheme.warning
                                : AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _medioLabel(MedioPago medio) {
    switch (medio) {
      case MedioPago.efectivo:
        return 'Efectivo';
      case MedioPago.transferencia:
        return 'Transferencia';
      case MedioPago.cheque:
        return 'Cheque';
    }
  }
}
