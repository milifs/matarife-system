// ============================================================
// FORMULARIO DE CARGA (compra de animales a un proveedor)
// ============================================================
// Es el bloque "Faena" del Excel. El kg de media res se completa DESPUÉS
// de faenar: hasta entonces queda vacío y el rinde no se puede calcular,
// pero el total a pagar ya queda definido (precio vivo x kg neto).
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';

class CargaFormScreen extends StatefulWidget {
  /// Si viene, es edición. Si no, alta.
  final Carga? cargaInicial;

  const CargaFormScreen({super.key, this.cargaInicial});

  @override
  State<CargaFormScreen> createState() => _CargaFormScreenState();
}

class _CargaFormScreenState extends State<CargaFormScreen> {
  String? _proveedorId;
  DateTime _fecha = DateTime.now();
  final _animalesCtrl = TextEditingController();
  final _kgVivoCtrl = TextEditingController();
  final _desvasteCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _rindeAseguradoCtrl = TextEditingController();
  final _kgMediaResCtrl = TextEditingController();
  final _observacionCtrl = TextEditingController();
  bool _guardando = false;

  bool get _esEdicion => widget.cargaInicial != null;

  @override
  void initState() {
    super.initState();
    final c = widget.cargaInicial;
    if (c != null) {
      _proveedorId = c.proveedorId;
      _fecha = c.fecha;
      _animalesCtrl.text = c.cantidadAnimales.toString();
      _kgVivoCtrl.text = _sinCerosAlPedo(c.kgVivo);
      _desvasteCtrl.text = _sinCerosAlPedo(c.desvastePorcentaje);
      _precioCtrl.text = _sinCerosAlPedo(c.precioKgVivo);
      _rindeAseguradoCtrl.text = _sinCerosAlPedo(c.rindeAsegurado);
      _kgMediaResCtrl.text =
          c.kgMediaRes == null ? '' : _sinCerosAlPedo(c.kgMediaRes!);
      _observacionCtrl.text = c.observacion;
    }
  }

  @override
  void dispose() {
    _animalesCtrl.dispose();
    _kgVivoCtrl.dispose();
    _desvasteCtrl.dispose();
    _precioCtrl.dispose();
    _rindeAseguradoCtrl.dispose();
    _kgMediaResCtrl.dispose();
    _observacionCtrl.dispose();
    super.dispose();
  }

  /// Al elegir proveedor se copian SUS valores por defecto, pero solo en el
  /// alta: en una carga vieja los valores son los que se usaron ese día y
  /// no se pisan con los actuales.
  void _aplicarDefaultsProveedor(Proveedor p) {
    _desvasteCtrl.text = _sinCerosAlPedo(p.desvastePorcentaje);
    _precioCtrl.text = _sinCerosAlPedo(p.precioKgVivo);
    _rindeAseguradoCtrl.text = _sinCerosAlPedo(p.rindeAsegurado);
  }

  double get _kgVivo => _aDouble(_kgVivoCtrl.text);
  double get _desvaste => _aDouble(_desvasteCtrl.text);
  double get _precio => _aDouble(_precioCtrl.text);
  double get _kgNeto => _kgVivo * (100 - _desvaste) / 100;
  double get _totalAPagar => _kgNeto * _precio;
  double? get _kgMediaRes {
    final texto = _kgMediaResCtrl.text.trim();
    if (texto.isEmpty) return null;
    return _aDouble(texto);
  }

  double? get _rinde {
    final kg = _kgMediaRes;
    if (kg == null || _kgNeto == 0) return null;
    return kg * 100 / _kgNeto;
  }

  bool get _puedeGuardar =>
      !_guardando && _proveedorId != null && _kgVivo > 0 && _precio > 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    // En edición hay que poder ver el proveedor aunque esté inactivo
    final proveedores = _esEdicion
        ? app.proveedores
        : app.proveedoresActivos;

    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion
            ? 'Editar ${widget.cargaInicial!.numeroFormateado}'
            : 'Nueva carga'),
        actions: [
          if (_esEdicion)
            IconButton(
              tooltip: 'Eliminar carga',
              icon: const Icon(Icons.delete_outline),
              onPressed: _eliminar,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Proveedor ──
          DropdownButtonFormField<String>(
            value: proveedores.any((p) => p.id == _proveedorId)
                ? _proveedorId
                : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Proveedor',
              prefixIcon: Icon(Icons.person_outline),
            ),
            items: proveedores
                .map((p) => DropdownMenuItem(
                      value: p.id,
                      // El tipo al lado del nombre: dos proveedores pueden
                      // llamarse parecido y uno vender cerdo.
                      child: Text('${p.nombre} · ${p.tipoLabel}'),
                    ))
                .toList(),
            onChanged: (v) {
              setState(() {
                _proveedorId = v;
                final p = app.proveedorPorId(v ?? '');
                if (p != null && !_esEdicion) _aplicarDefaultsProveedor(p);
              });
            },
          ),
          const SizedBox(height: 12),

          // ── Fecha ──
          InkWell(
            onTap: _elegirFecha,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha de la carga',
                prefixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(formatFecha(_fecha)),
            ),
          ),
          const SizedBox(height: 12),

          // ── Animales y kg vivo ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _animalesCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Animales',
                    prefixIcon: Icon(Icons.numbers, size: 18),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _kgVivoCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [MilesInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Kg vivo',
                    suffixText: 'kg',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Desvaste y precio ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _desvasteCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [MilesInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Desvaste',
                    suffixText: '%',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _precioCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [MilesInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Precio kg vivo',
                    prefixText: '\$ ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Resultado de la faena ──
          TextField(
            controller: _kgMediaResCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [MilesInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Kg media res (después de faenar)',
              helperText: 'Dejalo vacío si todavía no se faenó',
              suffixText: 'kg',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _rindeAseguradoCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [MilesInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Rinde asegurado',
              helperText: 'El rinde que prometió el proveedor para esta carga',
              suffixText: '%',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _observacionCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observación (opcional)',
            ),
          ),
          const SizedBox(height: 16),

          // ── Panel calculado ──
          _PanelCalculado(
            kgNeto: _kgNeto,
            totalAPagar: _totalAPagar,
            rinde: _rinde,
            desvaste: _desvaste,
          ),
          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: _puedeGuardar ? _guardar : null,
            icon: _guardando
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_esEdicion ? 'Guardar cambios' : 'Registrar carga'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Future<void> _elegirFecha() async {
    final elegida = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (elegida != null) setState(() => _fecha = elegida);
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    final app = context.read<AppProvider>();

    final base = widget.cargaInicial;
    final carga = Carga(
      id: base?.id,
      numero: base?.numero ?? 0,
      proveedorId: _proveedorId!,
      fecha: _fecha,
      cantidadAnimales: int.tryParse(_animalesCtrl.text.trim()) ?? 0,
      kgVivo: _kgVivo,
      desvastePorcentaje: _desvaste,
      precioKgVivo: _precio,
      rindeAsegurado: _aDouble(_rindeAseguradoCtrl.text),
      kgMediaRes: _kgMediaRes,
      observacion: _observacionCtrl.text.trim(),
      registradoPor: base?.registradoPor ?? app.usuarioActual?.nombreCompleto,
      creadoEn: base?.creadoEn,
    );

    final resultado = _esEdicion
        ? await app.actualizarCarga(carga)
        : await app.crearCarga(carga);

    if (!mounted) return;
    setState(() => _guardando = false);

    if (resultado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(app.error ?? 'No se pudo guardar la carga'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_esEdicion
            ? 'Carga actualizada'
            : 'Carga ${resultado.numeroFormateado} registrada'),
      ),
    );
    Navigator.pop(context, resultado);
  }

  /// Eliminar pide observación obligatoria: la carga se va con sus pagos y
  /// queda registrada en la auditoría.
  Future<void> _eliminar() async {
    final carga = widget.cargaInicial!;
    final app = context.read<AppProvider>();
    final pagos = app.pagosDeCarga(carga.id).length;
    final obsCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar ${carga.numeroFormateado}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pagos > 0
                  ? 'Se van a borrar también los $pagos pago(s) registrados '
                      'en esta carga. El saldo del proveedor se recalcula.'
                  : 'El saldo del proveedor se recalcula.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: obsCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Motivo (obligatorio)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () {
              if (obsCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    final ok = await app.eliminarCarga(carga, obsCtrl.text.trim());
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(app.error ?? 'No se pudo eliminar'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Carga eliminada')),
    );
    // Dos pop: cierra el form y el detalle, que ya no existe
    Navigator.pop(context, 'eliminada');
  }
}

// ─────────────────────────────────────────────
// Panel con lo que calcula el sistema
// ─────────────────────────────────────────────
class _PanelCalculado extends StatelessWidget {
  final double kgNeto;
  final double totalAPagar;
  final double? rinde;
  final double desvaste;

  const _PanelCalculado({
    required this.kgNeto,
    required this.totalAPagar,
    required this.rinde,
    required this.desvaste,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppTheme.infoBg,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Lo calcula el sistema',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.info,
              ),
            ),
            const SizedBox(height: 10),
            _Fila(
              label: 'Kg neto con desvaste (${formatPorcentaje(desvaste)})',
              valor: formatKg(kgNeto),
            ),
            _Fila(
              label: 'Rinde de la carga',
              valor: rinde == null ? 'Falta faena' : formatPorcentaje(rinde!),
            ),
            const Divider(height: 18),
            _Fila(
              label: 'TOTAL A PAGAR',
              valor: formatPesos(totalAPagar),
              destacado: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String label;
  final String valor;
  final bool destacado;

  const _Fila({
    required this.label,
    required this.valor,
    this.destacado = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: destacado ? 13 : 12,
                fontWeight: destacado ? FontWeight.w700 : FontWeight.w400,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              fontSize: destacado ? 16 : 13,
              fontWeight: destacado ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Los campos numéricos usan MilesInputFormatter, así que el texto viene con
// puntos de miles: parseNumero/textoMiles son los que entienden ese formato.
double _aDouble(String texto) => parseNumero(texto);

/// 3170.0 -> "3.170" ; 5.5 -> "5,5"
String _sinCerosAlPedo(double v) => textoMiles(v);
