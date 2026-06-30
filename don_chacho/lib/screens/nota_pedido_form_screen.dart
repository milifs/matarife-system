// ============================================================
// FORMULARIO NOTA DE PEDIDO - Para secretaria
// ============================================================
// Cliente: de lista existente O texto libre
// Filas dinámicas: descripción, cant medias, kg por media,
// precio por media, total calculado automáticamente
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';

class NotaPedidoFormScreen extends StatefulWidget {
  final NotaPedido? ndpInicial;

  const NotaPedidoFormScreen({super.key, this.ndpInicial});

  @override
  State<NotaPedidoFormScreen> createState() => _NotaPedidoFormScreenState();
}

class _NotaPedidoFormScreenState extends State<NotaPedidoFormScreen> {
  // Cliente
  bool _clienteDesLista = true;
  String? _clienteId;
  final _clienteLibreCtrl = TextEditingController();
  String _busquedaCliente = '';

  DateTime _fecha = DateTime.now();
  final List<_FilaForm> _filas = [];
  bool _guardando = false;

  bool get _esEdicion => widget.ndpInicial != null;

  double get _totalKg =>
      _filas.fold(0, (s, f) => s + f.totalKg);
  double get _totalPesos =>
      _filas.fold(0, (s, f) => s + f.totalPesos);

  bool get _clienteValido =>
      _clienteDesLista ? _clienteId != null : _clienteLibreCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final ndp = widget.ndpInicial;
    if (ndp != null) {
      _fecha = ndp.fecha;
      if (ndp.clienteId != null) {
        _clienteDesLista = true;
        _clienteId = ndp.clienteId;
      } else {
        _clienteDesLista = false;
        _clienteLibreCtrl.text = ndp.clienteNombreLibre ?? '';
      }
      for (final item in ndp.items) {
        _filas.add(_FilaForm.desdeItem(item));
      }
    }
    if (_filas.isEmpty) _filas.add(_FilaForm());
  }

  @override
  void dispose() {
    _clienteLibreCtrl.dispose();
    for (final f in _filas) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_clienteValido) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccioná o ingresá un cliente')),
      );
      return;
    }
    if (_filas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregá al menos una fila')),
      );
      return;
    }
    for (int i = 0; i < _filas.length; i++) {
      if (_filas[i].cantidadMedias < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fila ${i + 1}: ingresá la cantidad de medias')),
        );
        return;
      }
      if (_filas[i].kgControllers.any((c) => c.text.trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fila ${i + 1}: completá todos los campos de kg')),
        );
        return;
      }
    }

    setState(() => _guardando = true);

    final app = context.read<AppProvider>();
    final ndp = widget.ndpInicial != null
        ? (widget.ndpInicial!
          ..fecha = _fecha
          ..clienteId = _clienteDesLista ? _clienteId : null
          ..clienteNombreLibre =
              _clienteDesLista ? null : _clienteLibreCtrl.text.trim())
        : NotaPedido(
            fecha: _fecha,
            clienteId: _clienteDesLista ? _clienteId : null,
            clienteNombreLibre:
                _clienteDesLista ? null : _clienteLibreCtrl.text.trim(),
            estado: 'pendiente',
            creadoPor: app.usuarioActual?.id,
          );

    final items = _filas.map((f) => f.toItem(ndp.id)).toList();

    if (_esEdicion) {
      await app.actualizarNotaPedido(ndp, items);
    } else {
      await app.agregarNotaPedido(ndp, items);
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_esEdicion
              ? 'Nota de pedido actualizada'
              : 'Nota de pedido cargada y pendiente de confirmación'),
        ),
      );
    }
  }

  Future<void> _confirmarEliminar() async {
    final obsCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar nota de pedido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('¿Seguro que querés eliminar esta nota de pedido?'),
            const SizedBox(height: 14),
            TextField(
              controller: obsCtrl,
              decoration: const InputDecoration(
                labelText: 'Observación (opcional)',
                hintText: 'Ej: pedido duplicado, error de carga...',
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
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar',
                  style: TextStyle(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok != true) {
      obsCtrl.dispose();
      return;
    }
    final observacion =
        obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim();
    obsCtrl.dispose();
    if (mounted) {
      final app = context.read<AppProvider>();
      await app.eliminarNotaPedido(
        widget.ndpInicial!.id,
        observacion: observacion,
        eliminadoPor: app.usuarioActual?.nombreCompleto,
      );
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion ? 'Editar nota de pedido' : 'Nueva nota de pedido'),
        actions: [
          if (_esEdicion && app.tienePermiso('editar_remito'))
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
              onPressed: _guardando ? null : _confirmarEliminar,
              tooltip: 'Eliminar',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Selector tipo de cliente ──
          Row(
            children: [
              Expanded(
                child: _ToggleButton(
                  label: 'De lista',
                  icon: Icons.list_alt,
                  selected: _clienteDesLista,
                  onTap: () => setState(() {
                    _clienteDesLista = true;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ToggleButton(
                  label: 'Texto libre',
                  icon: Icons.edit_outlined,
                  selected: !_clienteDesLista,
                  onTap: () => setState(() {
                    _clienteDesLista = false;
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Cliente de lista ──
          if (_clienteDesLista) ...[
            TextField(
              decoration: InputDecoration(
                labelText: 'Buscar cliente',
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _busquedaCliente.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () =>
                            setState(() => _busquedaCliente = ''),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _busquedaCliente = v),
            ),
            const SizedBox(height: 8),
            Builder(builder: (context) {
              var ordenados = app.clientes.toList()
                ..sort((a, b) =>
                    a.nombreRazonSocial.compareTo(b.nombreRazonSocial));
              if (_busquedaCliente.isNotEmpty) {
                final q = _busquedaCliente.toLowerCase();
                ordenados = ordenados
                    .where((c) =>
                        c.nombreRazonSocial.toLowerCase().contains(q))
                    .toList();
              }
              return DropdownButtonFormField<String>(
                value: ordenados.any((c) => c.id == _clienteId)
                    ? _clienteId
                    : null,
                decoration: const InputDecoration(labelText: 'Cliente'),
                items: ordenados.map((c) {
                  final v = app.vendedorPorId(c.vendedorId);
                  return DropdownMenuItem(
                    value: c.id,
                    child: Text(
                      '${c.nombreRazonSocial} (${v?.apellido ?? ""})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => _clienteId = v),
              );
            }),
          ],

          // ── Cliente texto libre ──
          if (!_clienteDesLista)
            TextField(
              controller: _clienteLibreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre del cliente',
                hintText: 'Ej: VILLA, SUPER NORTE...',
              ),
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
            ),

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

          const SizedBox(height: 24),

          // ── Título filas ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Detalle',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary)),
              Text('${_filas.length} fila${_filas.length != 1 ? "s" : ""}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textHint)),
            ],
          ),
          const SizedBox(height: 10),

          // ── Filas dinámicas ──
          ..._filas.asMap().entries.map((entry) {
            final idx = entry.key;
            final fila = entry.value;
            return _FilaCard(
              key: ValueKey('fila_$idx'),
              fila: fila,
              index: idx,
              canRemove: _filas.length > 1,
              onRemove: () => setState(() {
                _filas[idx].dispose();
                _filas.removeAt(idx);
              }),
              onChanged: () => setState(() {}),
            );
          }),

          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _filas.add(_FilaForm())),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agregar fila'),
          ),

          const SizedBox(height: 20),

          // ── Totales ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _TotalRow(
                      label: 'Total kg', value: formatKg(_totalKg)),
                  const SizedBox(height: 8),
                  _TotalRow(
                    label: 'Total nota',
                    value: formatPesos(_totalPesos),
                    bold: true,
                    large: true,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Botón guardar ──
          if (!_esEdicion || app.tienePermiso('editar_remito'))
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_esEdicion
                        ? 'Guardar cambios'
                        : 'Cargar nota de pedido'),
              ),
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// CARD DE FILA
// ─────────────────────────────────────────────
class _FilaCard extends StatefulWidget {
  final _FilaForm fila;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _FilaCard({
    super.key,
    required this.fila,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  State<_FilaCard> createState() => _FilaCardState();
}

class _FilaCardState extends State<_FilaCard> {
  late TextEditingController _cantCtrl;
  late TextEditingController _descCtrl;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController(text: widget.fila.descripcion);
    _cantCtrl = TextEditingController(
        text: widget.fila.cantidadMedias > 0
            ? widget.fila.cantidadMedias.toString()
            : '');
  }

  @override
  void dispose() {
    _cantCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fila = widget.fila;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header fila
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppTheme.primary.withOpacity(0.15),
                  child: Text('${widget.index + 1}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                const Text('Fila',
                    style: TextStyle(
                        fontSize: 13, color: AppTheme.textSecondary)),
                const Spacer(),
                if (widget.canRemove)
                  IconButton(
                    icon: const Icon(Icons.close,
                        size: 18, color: AppTheme.danger),
                    onPressed: widget.onRemove,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Descripción
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                hintText: 'Ej: Carnicería Norte, Novillo...',
                isDense: true,
              ),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (v) {
                fila.descripcion = v;
                widget.onChanged();
              },
            ),
            const SizedBox(height: 10),

            // Cantidad medias
            TextField(
              controller: _cantCtrl,
              decoration: const InputDecoration(
                labelText: 'Cantidad de medias',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) {
                final n = int.tryParse(v) ?? 0;
                if (n != fila.cantidadMedias) {
                  setState(() => fila.setCantidad(n));
                  widget.onChanged();
                }
              },
            ),
            const SizedBox(height: 10),

            // Campos de kg por media
            if (fila.cantidadMedias > 0) ...[
              Text(
                'Kg por media (${fila.cantidadMedias} campo${fila.cantidadMedias != 1 ? "s" : ""})',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: fila.kgControllers.asMap().entries.map((e) {
                  final i = e.key;
                  final ctrl = e.value;
                  return SizedBox(
                    width: 90,
                    child: TextField(
                      controller: ctrl,
                      decoration: InputDecoration(
                        labelText: 'Media ${i + 1}',
                        isDense: true,
                        suffixText: 'kg',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[\d.,]')),
                      ],
                      onChanged: (_) => widget.onChanged(),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total kg fila',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary)),
                    Text(
                      formatKg(fila.totalKg),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Precio por kg
            TextField(
              controller: fila.precioCtrl,
              decoration: const InputDecoration(
                labelText: 'Precio por kg (\$)',
                isDense: true,
                prefixText: '\$ ',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              onChanged: (_) => widget.onChanged(),
            ),
            const SizedBox(height: 8),

            // Total fila
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Subtotal: ${formatPesos(fila.totalPesos)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// MODELO DE FILA EN MEMORIA
// ─────────────────────────────────────────────
class _FilaForm {
  String descripcion = '';
  int cantidadMedias = 0;
  List<TextEditingController> kgControllers = [];
  final TextEditingController precioCtrl = TextEditingController();

  _FilaForm();

  factory _FilaForm.desdeItem(NotaPedidoItem item) {
    final f = _FilaForm();
    f.descripcion = item.descripcion;
    f.cantidadMedias = item.cantidadMedias;
    f.kgControllers = item.kgsPorMedia
        .map((kg) => TextEditingController(
            text: kg == kg.truncateToDouble()
                ? kg.toInt().toString()
                : kg.toString()))
        .toList();
    f.precioCtrl.text = item.precioPorMedia == item.precioPorMedia.truncateToDouble()
        ? item.precioPorMedia.toInt().toString()
        : item.precioPorMedia.toString();
    return f;
  }

  void setCantidad(int n) {
    if (n < 0) return;
    while (kgControllers.length < n) {
      kgControllers.add(TextEditingController());
    }
    while (kgControllers.length > n) {
      kgControllers.removeLast().dispose();
    }
    cantidadMedias = n;
  }

  double _parseNum(String s) =>
      double.tryParse(s.replaceAll(',', '.')) ?? 0.0;

  double get totalKg =>
      kgControllers.fold(0, (s, c) => s + _parseNum(c.text));
  double get totalPesos =>
      totalKg * _parseNum(precioCtrl.text);

  NotaPedidoItem toItem(String ndpId) => NotaPedidoItem(
        notaPedidoId: ndpId,
        descripcion: descripcion,
        cantidadMedias: cantidadMedias,
        kgsPorMedia: kgControllers
            .map((c) => _parseNum(c.text))
            .toList(),
        precioPorMedia: _parseNum(precioCtrl.text),
      );

  void dispose() {
    for (final c in kgControllers) {
      c.dispose();
    }
    precioCtrl.dispose();
  }
}

// ─────────────────────────────────────────────
// WIDGETS AUXILIARES
// ─────────────────────────────────────────────
class _ToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withOpacity(0.12)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppTheme.primary : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? AppTheme.primary : AppTheme.textHint),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppTheme.primary : AppTheme.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool large;

  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontSize: large ? 17 : 14,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style.copyWith(color: AppTheme.primary)),
      ],
    );
  }
}
