// ============================================================
// PANTALLA DE COSTOS SEMANALES
// ============================================================
// Lista todas las semanas con costo cargado (novillo y cerdo)
// Permite editar costos de semanas anteriores.
// Editar un costo viejo RECALCULA ganancias históricas.
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';

class CostosSemanaScreen extends StatefulWidget {
  const CostosSemanaScreen({super.key});

  @override
  State<CostosSemanaScreen> createState() => _CostosSemanaScreenState();
}

class _CostosSemanaScreenState extends State<CostosSemanaScreen> {
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    await context.read<AppProvider>().cargarCostosSemanales();
    if (mounted) setState(() => _cargando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Costos por semana'),
      ),
      body: Consumer<AppProvider>(
        builder: (context, app, _) {
          if (_cargando) {
            return const Center(child: CircularProgressIndicator());
          }

          final costos = app.costosSemanales;

          if (costos.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.savings_outlined,
                      size: 48, color: AppTheme.textHint),
                  const SizedBox(height: 12),
                  const Text('No hay costos cargados',
                      style: TextStyle(
                          fontSize: 14, color: AppTheme.textSecondary)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _editarCosto(context, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Cargar primera semana'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: costos.length,
            itemBuilder: (context, i) {
              final c = costos[i];
              final esActual = _esSemanaActual(c.semanaInicio);
              final hoy = DateTime.now();
              final hoyLunes = DateTime(hoy.year, hoy.month, hoy.day)
                  .subtract(Duration(days: hoy.weekday - 1));
              final esPasado = c.semanaInicio.isBefore(hoyLunes);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => _editarCosto(context, c),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatRangoSemana(c.semanaInicio),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (esActual)
                              const StatusPill(
                                text: 'Actual',
                                type: StatusType.success,
                              )
                            else if (esPasado)
                              const StatusPill(
                                text: 'Histórica',
                                type: StatusType.info,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('Novillo',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme
                                              .textSecondary)),
                                  Text(
                                    '${formatPesos(c.costoPorKgNovillo)}/kg',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('Cerdo',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppTheme
                                              .textSecondary)),
                                  Text(
                                    '${formatPesos(c.costoPorKgCerdo)}/kg',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.edit,
                                size: 18, color: AppTheme.textHint),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editarCosto(context, null),
        tooltip: 'Agregar/editar semana',
        child: const Icon(Icons.add),
      ),
    );
  }

  bool _esSemanaActual(DateTime semanaInicio) {
    final hoy = DateTime.now();
    final lunesHoy = hoy.subtract(Duration(days: hoy.weekday - 1));
    final lunesNorm =
        DateTime(lunesHoy.year, lunesHoy.month, lunesHoy.day);
    final cLunes = DateTime(
        semanaInicio.year, semanaInicio.month, semanaInicio.day);
    return cLunes.isAtSameMomentAs(lunesNorm);
  }

  Future<void> _editarCosto(
      BuildContext context, CostoSemanal? existente) async {
    final result = await showModalBottomSheet<CostoSemanal>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CostoEditor(existente: existente),
    );

    if (result == null || !mounted) return;

    // Si es una semana vieja (no la actual), alertar
    final esVieja = !_esSemanaActual(result.semanaInicio) &&
        existente != null;
    if (esVieja) {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Editar semana anterior?'),
          content: const Text(
              'Estás editando el costo de una semana pasada. Esto va a recalcular todas las ganancias históricas de esa semana. ¿Querés continuar?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (confirmado != true) return;
    }

    if (!mounted) return;
    await context.read<AppProvider>().guardarCostoSemana(result);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Costo guardado'),
          backgroundColor: AppTheme.success,
        ),
      );
    }
  }
}

// ─────────────────────────────────────────────
// Editor modal de costo
// ─────────────────────────────────────────────
class _CostoEditor extends StatefulWidget {
  final CostoSemanal? existente;

  const _CostoEditor({this.existente});

  @override
  State<_CostoEditor> createState() => _CostoEditorState();
}

class _CostoEditorState extends State<_CostoEditor> {
  late DateTime _semanaInicio;
  final _novilloCtrl = TextEditingController();
  final _cerdoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existente != null) {
      _semanaInicio = widget.existente!.semanaInicio;
      _novilloCtrl.text =
          widget.existente!.costoPorKgNovillo.toStringAsFixed(0);
      _cerdoCtrl.text =
          widget.existente!.costoPorKgCerdo.toStringAsFixed(0);
    } else {
      // Semana actual por defecto
      final hoy = DateTime.now();
      final lunes = hoy.subtract(Duration(days: hoy.weekday - 1));
      _semanaInicio = DateTime(lunes.year, lunes.month, lunes.day);
    }
  }

  @override
  void dispose() {
    _novilloCtrl.dispose();
    _cerdoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existente != null
                ? 'Editar costo'
                : 'Nuevo costo semanal',
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          // Selector de semana (muestra rango)
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _semanaInicio,
                firstDate: DateTime(2024),
                lastDate: DateTime.now().add(const Duration(days: 7)),
                locale: const Locale('es'),
                helpText: 'Elegir un día de la semana',
              );
              if (picked != null) {
                final lunes =
                    picked.subtract(Duration(days: picked.weekday - 1));
                setState(() {
                  _semanaInicio =
                      DateTime(lunes.year, lunes.month, lunes.day);
                });
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Semana',
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(
                formatRangoSemana(_semanaInicio),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _novilloCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Costo/kg Novillo',
              prefixText: '\$ ',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _cerdoCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Costo/kg Cerdo',
              prefixText: '\$ ',
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _guardar,
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _guardar() {
    // Aceptar números con punto como separador de miles o sin separador
    final novilloStr = _novilloCtrl.text
        .replaceAll('.', '')
        .replaceAll(',', '.');
    final cerdoStr = _cerdoCtrl.text
        .replaceAll('.', '')
        .replaceAll(',', '.');
    final novillo = double.tryParse(novilloStr) ?? 0;
    final cerdo = double.tryParse(cerdoStr) ?? 0;

    if (novillo <= 0 && cerdo <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cargá al menos un costo'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    final costo = CostoSemanal(
      id: widget.existente?.id,
      semanaInicio: _semanaInicio,
      costoPorKgNovillo: novillo,
      costoPorKgCerdo: cerdo,
    );

    Navigator.pop(context, costo);
  }
}
