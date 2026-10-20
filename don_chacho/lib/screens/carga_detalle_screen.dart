// ============================================================
// DETALLE DE CARGA — Espejo del Excel "Proveedores-Pagos"
// ============================================================
// Tres bloques, en el mismo orden que la planilla:
//   1. FAENA     → lo comprado (animales, kg vivo, desvaste, precio, rinde)
//   2. PAGOS     → saldo que viene arrastrado + cada pago + saldo final
//   3. DIFERENCIA DE RINDE → cuánto se perdió/ganó contra el rinde asegurado
//
// El saldo anterior NO se guarda: se recalcula en cadena desde la primera
// carga del proveedor. Por eso si se corrige una carga vieja, todas las
// siguientes se reacomodan solas.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';
import 'carga_form_screen.dart';

class CargaDetalleScreen extends StatefulWidget {
  final String cargaId;

  const CargaDetalleScreen({super.key, required this.cargaId});

  @override
  State<CargaDetalleScreen> createState() => _CargaDetalleScreenState();
}

class _CargaDetalleScreenState extends State<CargaDetalleScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        final carga = app.cargaPorId(widget.cargaId);

        // Si la borraron desde el formulario, cerramos la pantalla.
        if (carga == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Carga')),
            body: const Center(
              child: Text(
                'La carga ya no existe',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          );
        }

        final pagos = app.pagosDeCarga(carga.id);
        final saldoAnterior = app.saldoAnteriorDeCarga(carga);
        final pagado = app.totalPagadoCarga(carga.id);
        final saldoFinal = app.saldoDeCarga(carga);

        return Scaffold(
          appBar: AppBar(
            title: Text(carga.numeroFormateado),
            actions: [
              IconButton(
                tooltip: 'Editar carga',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editarCarga(carga),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _editarPago(carga, null),
            icon: const Icon(Icons.add),
            label: const Text('Registrar pago'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            children: [
              _Encabezado(carga: carga, app: app),
              const SizedBox(height: 12),
              _BloqueFaena(
                carga: carga,
                onCargarFaena: () => _cargarFaena(carga),
              ),
              const SizedBox(height: 12),
              _BloquePagos(
                carga: carga,
                pagos: pagos,
                saldoAnterior: saldoAnterior,
                pagado: pagado,
                saldoFinal: saldoFinal,
                onTapPago: (p) => _editarPago(carga, p),
              ),
              const SizedBox(height: 12),
              _BloqueRinde(carga: carga),
              if (carga.observacion.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                _BloqueObservacion(texto: carga.observacion),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Editar la carga (abre el formulario completo) ──
  Future<void> _editarCarga(Carga carga) async {
    final resultado = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => CargaFormScreen(cargaInicial: carga),
      ),
    );
    if (!mounted) return;
    // Si la eliminaron desde el formulario, volvemos a la lista.
    if (resultado == 'eliminada') Navigator.pop(context);
  }

  // ── Atajo: cargar el kg de media res después de la faena ──
  Future<void> _cargarFaena(Carga carga) async {
    final ctrl = TextEditingController(
      text: carga.kgMediaRes == null ? '' : _sinCeros(carga.kgMediaRes!),
    );

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resultado de faena'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Kg neto con desvaste: ${formatKg(carga.kgNeto)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Kg media res',
                suffixText: 'kg',
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
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (guardar != true || !mounted) return;

    final texto = ctrl.text.trim();
    final app = context.read<AppProvider>();
    final actualizada = await app.actualizarCarga(
      texto.isEmpty
          ? carga.copyWith(limpiarKgMediaRes: true)
          : carga.copyWith(kgMediaRes: _aDouble(texto)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          actualizada == null ? 'No se pudo guardar' : 'Faena registrada',
        ),
      ),
    );
  }

  // ── Alta / edición de un pago ──
  Future<void> _editarPago(Carga carga, CargaPago? pago) async {
    final esNuevo = pago == null;
    var fecha = pago?.fecha ?? DateTime.now();
    var medio = pago?.medio ?? 'transferencia';
    final montoCtrl = TextEditingController(
      text: pago == null ? '' : _sinCeros(pago.monto),
    );

    final accion = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: 20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                esNuevo ? 'Registrar pago' : 'Editar pago',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${carga.numeroFormateado} · falta pagar '
                '${formatPesos(context.read<AppProvider>().saldoDeCarga(carga).abs())}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final elegida = await showDatePicker(
                    context: ctx,
                    initialDate: fecha,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2100),
                  );
                  if (elegida != null) setLocal(() => fecha = elegida);
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha del pago',
                    prefixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(formatFecha(fecha)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: medio,
                decoration: const InputDecoration(labelText: 'Medio de pago'),
                items: const [
                  DropdownMenuItem(
                    value: 'efectivo',
                    child: Text('Efectivo'),
                  ),
                  DropdownMenuItem(
                    value: 'transferencia',
                    child: Text('Transferencia'),
                  ),
                  DropdownMenuItem(
                    value: 'cheque',
                    child: Text('Cheque'),
                  ),
                ],
                onChanged: (v) => setLocal(() => medio = v ?? 'efectivo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: montoCtrl,
                autofocus: esNuevo,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixText: '\$ ',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (!esNuevo)
                    IconButton(
                      tooltip: 'Eliminar pago',
                      icon: const Icon(Icons.delete_outline,
                          color: AppTheme.danger),
                      onPressed: () => Navigator.pop(ctx, 'eliminar'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, 'cancelar'),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      if (_aDouble(montoCtrl.text) <= 0) return;
                      Navigator.pop(ctx, 'guardar');
                    },
                    child: const Text('Guardar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || accion == null || accion == 'cancelar') return;

    if (accion == 'eliminar') {
      await _eliminarPago(pago!);
      return;
    }

    final app = context.read<AppProvider>();
    final nuevo = CargaPago(
      id: pago?.id,
      cargaId: carga.id,
      fecha: fecha,
      medio: medio,
      monto: _aDouble(montoCtrl.text),
      registradoPor: pago?.registradoPor ?? app.usuarioActual?.nombreCompleto,
      creadoEn: pago?.creadoEn,
    );
    final ok = await app.guardarPagoCarga(nuevo, esNuevo: esNuevo);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Pago guardado' : 'No se pudo guardar')),
    );
  }

  // ── Baja de un pago: exige motivo y queda auditado ──
  Future<void> _eliminarPago(CargaPago pago) async {
    final obsCtrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Eliminar pago'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Se va a eliminar el pago de ${formatPesos(pago.monto)} '
                '(${pago.medioLabel}) del ${formatFecha(pago.fecha)}.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: obsCtrl,
                autofocus: true,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  helperText: 'Queda guardado en el historial',
                ),
                onChanged: (_) => setLocal(() {}),
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
              onPressed: obsCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      ),
    );

    if (confirmar != true || !mounted) return;

    final ok = await context
        .read<AppProvider>()
        .eliminarPagoCarga(pago, obsCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Pago eliminado' : 'No se pudo eliminar')),
    );
  }
}

// ─────────────────────────────────────────────
// Encabezado: proveedor y fecha de la carga
// ─────────────────────────────────────────────
class _Encabezado extends StatelessWidget {
  final Carga carga;
  final AppProvider app;

  const _Encabezado({required this.carga, required this.app});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.nombreProveedor(carga.proveedorId),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatFecha(carga.fecha),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (!carga.tieneFaena)
              const StatusPill(text: 'Falta faena', type: StatusType.warning),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Bloque FAENA (lo comprado)
// ─────────────────────────────────────────────
class _BloqueFaena extends StatelessWidget {
  final Carga carga;
  final VoidCallback onCargarFaena;

  const _BloqueFaena({required this.carga, required this.onCargarFaena});

  @override
  Widget build(BuildContext context) {
    final rinde = carga.rindeCarga;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TituloBloque(texto: 'FAENA'),
            const SizedBox(height: 12),
            _Fila(
              label: 'Animales',
              valor: '${carga.cantidadAnimales}',
            ),
            _Fila(label: 'Kg vivo', valor: formatKg(carga.kgVivo)),
            _Fila(
              label: 'Desvaste',
              valor: formatPorcentaje(carga.desvastePorcentaje),
            ),
            _Fila(
              label: 'Kg neto con desvaste',
              valor: formatKg(carga.kgNeto),
              destacado: true,
            ),
            _Fila(
              label: 'Precio kg vivo',
              valor: '${formatPesos(carga.precioKgVivo)}/kg',
            ),
            const Divider(height: 20),
            if (carga.tieneFaena) ...[
              _Fila(
                label: 'Kg media res',
                valor: formatKg(carga.kgMediaRes!),
              ),
              _Fila(
                label: 'Rinde de la carga',
                valor: rinde == null ? '—' : formatPorcentaje(rinde),
                destacado: true,
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Todavía no se cargó el kg de media res',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onCargarFaena,
                      icon: const Icon(Icons.scale_outlined, size: 18),
                      label: const Text('Cargar faena'),
                    ),
                  ],
                ),
              ),
            const Divider(height: 20),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'TOTAL A PAGAR',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Text(
                  formatPesos(carga.totalAPagar),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
            if (carga.tieneFaena)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onCargarFaena,
                  icon: const Icon(Icons.scale_outlined, size: 16),
                  label: const Text('Corregir kg media res'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Bloque PAGOS (igual al Excel: arrastre + pagos + saldo)
// ─────────────────────────────────────────────
class _BloquePagos extends StatelessWidget {
  final Carga carga;
  final List<CargaPago> pagos;
  final double saldoAnterior;
  final double pagado;
  final double saldoFinal;
  final ValueChanged<CargaPago> onTapPago;

  const _BloquePagos({
    required this.carga,
    required this.pagos,
    required this.saldoAnterior,
    required this.pagado,
    required this.saldoFinal,
    required this.onTapPago,
  });

  @override
  Widget build(BuildContext context) {
    final debe = saldoFinal < -0.5;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TituloBloque(texto: 'PAGOS'),
            const SizedBox(height: 12),
            // Primera línea: lo que venía arrastrado de la carga anterior
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Saldo anterior',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    saldoAnterior.abs() < 0.5
                        ? formatPesos(0)
                        : '${saldoAnterior < 0 ? "-" : "+"}'
                            '${formatPesos(saldoAnterior.abs())}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: saldoAnterior < -0.5
                          ? AppTheme.danger
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 8),
            if (pagos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Todavía no se registraron pagos de esta carga',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              )
            else
              ...pagos.map(
                (p) => InkWell(
                  onTap: () => onTapPago(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      children: [
                        Icon(_iconoMedio(p.medio),
                            size: 17, color: AppTheme.textHint),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.medioLabel,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                formatFecha(p.fecha),
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textHint,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatPesos(p.monto),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.success,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right,
                            size: 18, color: AppTheme.textHint),
                      ],
                    ),
                  ),
                ),
              ),
            const Divider(height: 18),
            _Fila(
              label: 'Total pagado de esta carga',
              valor: formatPesos(pagado),
            ),
            _Fila(
              label: 'Total a pagar',
              valor: '-${formatPesos(carga.totalAPagar)}',
            ),
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    debe ? 'SALDO (se le debe)' : 'SALDO A FAVOR',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Text(
                  '${debe ? "-" : ""}${formatPesos(saldoFinal.abs())}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: debe ? AppTheme.danger : AppTheme.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'El saldo se arrastra a la próxima carga de este proveedor',
              style: TextStyle(fontSize: 11, color: AppTheme.textHint),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconoMedio(String medio) {
    switch (medio) {
      case 'transferencia':
        return Icons.account_balance_outlined;
      case 'cheque':
        return Icons.receipt_long_outlined;
      default:
        return Icons.payments_outlined;
    }
  }
}

// ─────────────────────────────────────────────
// Bloque DIFERENCIA DE RINDE
// ─────────────────────────────────────────────
// Cuánto se pagó de más (o de menos) respecto del rinde que el proveedor
// aseguró. Positivo en kg = rindió menos de lo prometido.
class _BloqueRinde extends StatelessWidget {
  final Carga carga;

  const _BloqueRinde({required this.carga});

  @override
  Widget build(BuildContext context) {
    final difKg = carga.diferenciaRindeKg;
    final difPesos = carga.diferenciaRindePesos;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TituloBloque(texto: 'DIFERENCIA DE RINDE'),
            const SizedBox(height: 12),
            _Fila(
              label: 'Rinde asegurado',
              valor: formatPorcentaje(carga.rindeAsegurado),
            ),
            _Fila(
              label: 'Kg esperados',
              valor: formatKg(carga.kgEsperados),
            ),
            if (!carga.tieneFaena)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Se calcula cuando se cargue el kg de media res',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              )
            else ...[
              _Fila(
                label: 'Kg obtenidos',
                valor: formatKg(carga.kgMediaRes!),
              ),
              const Divider(height: 18),
              _Fila(
                label: difKg! > 0 ? 'Rindió de menos' : 'Rindió de más',
                valor: formatKg(difKg.abs()),
                destacado: true,
                color: difKg > 0 ? AppTheme.danger : AppTheme.success,
              ),
              _Fila(
                label: 'Valorizado',
                valor: formatPesos(difPesos!.abs()),
                destacado: true,
                color: difKg > 0 ? AppTheme.danger : AppTheme.success,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Observación de la carga
// ─────────────────────────────────────────────
class _BloqueObservacion extends StatelessWidget {
  final String texto;

  const _BloqueObservacion({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TituloBloque(texto: 'OBSERVACIÓN'),
            const SizedBox(height: 8),
            Text(texto, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Piezas chicas reutilizadas
// ─────────────────────────────────────────────
class _TituloBloque extends StatelessWidget {
  final String texto;

  const _TituloBloque({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppTheme.textHint,
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  final String label;
  final String valor;
  final bool destacado;
  final Color? color;

  const _Fila({
    required this.label,
    required this.valor,
    this.destacado = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              fontSize: 13,
              fontWeight: destacado ? FontWeight.w700 : FontWeight.w600,
              color: color ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

double _aDouble(String texto) =>
    double.tryParse(texto.trim().replaceAll(',', '.')) ?? 0;

String _sinCeros(double valor) =>
    valor == valor.roundToDouble() ? valor.toInt().toString() : valor.toString();
