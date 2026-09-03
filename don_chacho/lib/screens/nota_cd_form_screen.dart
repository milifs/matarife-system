// ============================================================
// FORMULARIO NOTA DE CRÉDITO / DÉBITO
// ============================================================
// NC (crédito): resta al saldo del cliente (a su favor).
// ND (débito):  suma al saldo del cliente (cargo extra).
// Lo pueden registrar todos los usuarios (admin y cajeras).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/estado_cuenta_service.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';

class NotaCdFormScreen extends StatefulWidget {
  final Cliente? clienteInicial;
  final String? tipoInicial; // 'credito' | 'debito'
  final NotaCreditoDebito? notaInicial; // si viene → modo ver (solo lectura)

  const NotaCdFormScreen({
    super.key,
    this.clienteInicial,
    this.tipoInicial,
    this.notaInicial,
  });

  @override
  State<NotaCdFormScreen> createState() => _NotaCdFormScreenState();
}

class _NotaCdFormScreenState extends State<NotaCdFormScreen> {
  String? _clienteId;
  final TextEditingController _busquedaCtrl = TextEditingController();
  final TextEditingController _montoCtrl = TextEditingController();
  final TextEditingController _motivoCtrl = TextEditingController();
  bool _mostrarSugerencias = false;
  String _tipo = 'credito';
  DateTime _fecha = DateTime.now();
  bool _guardando = false;

  bool get _soloLectura => widget.notaInicial != null;

  @override
  void initState() {
    super.initState();
    final nota = widget.notaInicial;
    if (nota != null) {
      _clienteId = nota.clienteId;
      _tipo = nota.tipo;
      _fecha = nota.fecha;
      _montoCtrl.text = nota.monto.toString();
      _motivoCtrl.text = nota.motivo;
      return;
    }
    _clienteId = widget.clienteInicial?.id;
    if (widget.tipoInicial != null) _tipo = widget.tipoInicial!;
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    _montoCtrl.dispose();
    _motivoCtrl.dispose();
    super.dispose();
  }

  double get _monto =>
      double.tryParse(_montoCtrl.text.replaceAll(',', '.')) ?? 0;

  bool get _esCredito => _tipo == 'credito';

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final saldoCliente =
        _clienteId != null ? app.getSaldoCliente(_clienteId!) : 0.0;
    final cliente =
        _clienteId != null ? app.clientePorId(_clienteId!) : null;
    final vendedor =
        cliente != null ? app.vendedorPorId(cliente.vendedorId) : null;

    // Saldo resultante: NC resta, ND suma.
    final saldoResultante =
        saldoCliente + (_esCredito ? -_monto : _monto);

    if (_soloLectura) {
      return _buildSoloLectura(app, cliente, vendedor, saldoCliente);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nota de crédito / débito'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Tipo ──
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'credito',
                label: Text('Crédito'),
                icon: Icon(Icons.remove_circle_outline, size: 18),
              ),
              ButtonSegment(
                value: 'debito',
                label: Text('Débito'),
                icon: Icon(Icons.add_circle_outline, size: 18),
              ),
            ],
            selected: {_tipo},
            onSelectionChanged: (s) => setState(() => _tipo = s.first),
          ),
          const SizedBox(height: 6),
          Text(
            _esCredito
                ? 'Resta al saldo del cliente (a su favor).'
                : 'Suma al saldo del cliente (cargo extra).',
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),

          // ── Cliente ──
          if (widget.clienteInicial != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppTheme.primary.withOpacity(0.25)),
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
            )
          else ...[
            TextField(
              controller: _busquedaCtrl,
              onChanged: (v) => setState(() {
                _clienteId = null;
                _mostrarSugerencias = v.isNotEmpty;
              }),
              onTapOutside: (_) => Future.delayed(
                const Duration(milliseconds: 150),
                () {
                  if (mounted) setState(() => _mostrarSugerencias = false);
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
            if (_mostrarSugerencias)
              Builder(builder: (_) {
                final q = normalizarBusqueda(_busquedaCtrl.text);
                final sugerencias = (app.clientes.toList()
                      ..sort((a, b) => a.nombreRazonSocial
                          .compareTo(b.nombreRazonSocial)))
                    .where((c) =>
                        normalizarBusqueda(c.nombreRazonSocial).contains(q))
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
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final c = sugerencias[i];
                      final v = app.vendedorPorId(c.vendedorId);
                      return InkWell(
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
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(cliente.nombreRazonSocial,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500)),
                              if (vendedor != null)
                                Text('Vendedor: ${vendedor.nombreCompleto}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Saldo actual',
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
                    const Divider(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Saldo resultante',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary)),
                        Text(
                          formatPesos(saldoResultante),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: saldoResultante > 0
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

          const SizedBox(height: 16),

          // ── Fecha ──
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _fecha,
                firstDate: DateTime(2024),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                locale: const Locale('es'),
              );
              if (picked != null) setState(() => _fecha = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha',
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(formatFecha(_fecha)),
            ),
          ),
          const SizedBox(height: 16),

          // ── Monto ──
          TextField(
            controller: _montoCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Monto',
              prefixText: r'$ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // ── Motivo ──
          TextField(
            controller: _motivoCtrl,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional)',
              hintText: 'Ej: devolución, bonificación, interés por mora...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _guardando || _clienteId == null || _monto <= 0
                ? null
                : _guardar,
            child: _guardando
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(_esCredito
                    ? 'Registrar nota de crédito'
                    : 'Registrar nota de débito'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ── Modo ver (solo lectura): abierto desde la ficha del cliente ──
  Widget _buildSoloLectura(
    AppProvider app,
    Cliente? cliente,
    Vendedor? vendedor,
    double saldoCliente,
  ) {
    final nota = widget.notaInicial!;
    final Color acento = nota.esCredito ? AppTheme.success : AppTheme.danger;

    return Scaffold(
      appBar: AppBar(
        title: Text('Ver ${nota.tipoLabel.toLowerCase()}'),
        actions: [
          if (app.tienePermiso('editar_pago'))
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Eliminar',
              onPressed: () => _eliminarNota(app, nota),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            nota.esCredito
                                ? Icons.remove_circle_outline
                                : Icons.add_circle_outline,
                            size: 20,
                            color: acento,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            nota.numeroFormateado,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      StatusPill(
                        text: nota.esCredito ? 'Crédito' : 'Débito',
                        type: nota.esCredito
                            ? StatusType.success
                            : StatusType.danger,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nota.esCredito
                        ? 'Resta al saldo del cliente (a su favor).'
                        : 'Suma al saldo del cliente (cargo extra).',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const Divider(height: 24),
                  _filaLectura('Cliente',
                      cliente?.nombreRazonSocial ?? '—'),
                  if (vendedor != null)
                    _filaLectura('Vendedor', vendedor.nombreCompleto),
                  _filaLectura('Fecha', formatFecha(nota.fecha)),
                  _filaLectura(
                    'Monto',
                    '${nota.esCredito ? '- ' : ''}${formatPesos(nota.monto)}',
                    valueColor: acento,
                    bold: true,
                  ),
                  if (nota.motivo.trim().isNotEmpty)
                    _filaLectura('Motivo', nota.motivo),
                  if ((nota.registradoPor ?? '').isNotEmpty)
                    _filaLectura('Registrado por', nota.registradoPor!),
                  const Divider(height: 24),
                  _filaLectura('Saldo actual del cliente',
                      formatPesos(saldoCliente),
                      valueColor: saldoCliente > 0
                          ? AppTheme.danger
                          : AppTheme.success,
                      bold: true),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _descargarComprobante(app, nota),
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text('Descargar comprobante'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _filaLectura(String label, String value,
      {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: bold ? 15 : 13,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _descargarComprobante(
      AppProvider app, NotaCreditoDebito nota) async {
    final cliente = app.clientePorId(nota.clienteId);
    if (cliente == null) return;
    final vendedor = app.vendedorPorId(cliente.vendedorId);
    await EstadoCuentaService.generarComprobanteNcd(
      nota: nota,
      cliente: cliente,
      vendedor: vendedor,
      saldoActual: app.getSaldoCliente(nota.clienteId),
    );
  }

  Future<void> _eliminarNota(
      AppProvider app, NotaCreditoDebito nota) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar ${nota.numeroFormateado}'),
        content: Text(
            '¿Seguro que querés eliminar esta ${nota.tipoLabel.toLowerCase()} de ${formatPesos(nota.monto)}? El saldo del cliente se recalcula.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar',
                style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await app.eliminarNotaCreditoDebito(nota.id,
        eliminadoPor: app.usuarioActual?.nombreCompleto);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${nota.numeroFormateado} eliminada')),
      );
      Navigator.pop(context, 'eliminada');
    }
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);

    final nota = NotaCreditoDebito(
      clienteId: _clienteId!,
      tipo: _tipo,
      fecha: _fecha,
      monto: _monto,
      motivo: _motivoCtrl.text.trim(),
      registradoPor:
          context.read<AppProvider>().usuarioActual?.nombreCompleto,
    );

    try {
      await context.read<AppProvider>().agregarNotaCreditoDebito(nota);
    } catch (e) {
      setState(() => _guardando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _guardando = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${_esCredito ? 'Nota de crédito' : 'Nota de débito'} registrada: ${formatPesos(_monto)}'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context, nota);
    }
  }
}
