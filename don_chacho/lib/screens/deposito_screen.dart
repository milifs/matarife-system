// ============================================================
// DEPÓSITO — Stock de medias reses (v19.5, reescrito en v19.16)
// ============================================================
// Es el libro de lo que hay en la cámara: se carga a mano lo que entra y lo
// que sale, y la pantalla muestra el saldo DESGLOSADO, porque un número sin
// explicación no se le cree.
//
//   lo que debería haber = arranque + entradas - salidas
//
// NO CRUZA NADA con el resto del sistema. Hasta v19.15 sumaba las cargas de
// proveedores y restaba los remitos confirmados; eso se sacó por decisión del
// usuario. El depósito dice qué hay, no lo reconcilia con lo que se compró ni
// con lo que se facturó.
//
// Lo único que sigue siendo una comparación es el RECUENTO: lo contado a mano
// contra lo que dice el libro, y contra el libro DE SU MOMENTO, no el de hoy
// (ver `stockDeposito` en app_provider). Eso es lo que delata a la media que
// salió sin que nadie la registre.
//
// Novillo y cerdo van separados, igual que la Lista de reparto: una media de
// cerdo no puede tapar un faltante de novillo.
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';

/// Tope de campos de kg que se generan. Un recuento de toda la cámara puede
/// ser grande y está bien, pero sin tope un error de tipeo ("1000" en vez de
/// "10") colgaría la pantalla generando mil campos.
const int _maxCamposKg = 120;

/// Deja la lista de controllers del largo que corresponde a las medias
/// tipeadas. Se llama en cada rebuild del formulario, así los campos aparecen
/// y desaparecen a medida que se escribe la cantidad.
void _sincronizarKg(List<TextEditingController> ctrls, double medias) {
  final objetivo =
      medias <= 0 ? 0 : medias.ceil().clamp(0, _maxCamposKg).toInt();
  while (ctrls.length < objetivo) {
    ctrls.add(TextEditingController());
  }
  while (ctrls.length > objetivo) {
    ctrls.removeLast().dispose();
  }
}

/// Los kilos efectivamente cargados, salteando los campos vacíos.
///
/// Los kg son opcionales (ver `DepositoMovimiento.kgsPorMedia`): se descarta
/// lo vacío en vez de guardar ceros, que ensuciarían el total y harían pasar
/// por pesada una media que nadie pesó.
List<double> _kgsCargados(List<TextEditingController> ctrls) => ctrls
    .map((c) => parseNumero(c.text))
    .where((kg) => kg > 0)
    .toList();

class DepositoScreen extends StatefulWidget {
  const DepositoScreen({super.key});

  @override
  State<DepositoScreen> createState() => _DepositoScreenState();
}

class _DepositoScreenState extends State<DepositoScreen> {
  @override
  void initState() {
    super.initState();
    // Lazy, igual que proveedores: nadie paga la query en el login.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppProvider>().cargarDeposito();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, app, _) {
        final novillo = app.stockNovillo;
        final cerdo = app.stockCerdo;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Depósito'),
            actions: [
              IconButton(
                tooltip: 'Arranque del depósito',
                icon: const Icon(Icons.tune),
                onPressed: () => _configurarArranque(app),
              ),
              IconButton(
                tooltip: 'Actualizar',
                icon: const Icon(Icons.refresh),
                onPressed: () => app.cargarDeposito(forzar: true),
              ),
            ],
          ),
          body: !app.depositoCargado
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => app.cargarDeposito(forzar: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      if (app.depositoSinConfigurar)
                        _SinConfigurar(
                          onConfigurar: () => _configurarArranque(app),
                        )
                      else ...[
                        _TarjetaStock(
                          stock: novillo,
                          onRecuento: () =>
                              _registrarRecuento(app, novillo),
                        ),
                        const SizedBox(height: 12),
                        _TarjetaStock(
                          stock: cerdo,
                          onRecuento: () => _registrarRecuento(app, cerdo),
                        ),
                        const SizedBox(height: 16),
                        _BotonesMovimiento(
                          onEntrada: () => _registrarMovimiento(
                            app,
                            DepositoMovimiento.claseEntrada,
                          ),
                          onSalida: () => _registrarMovimiento(
                            app,
                            DepositoMovimiento.claseSalida,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _Historial(
                          movimientos: app.movimientosDeposito(),
                          onTap: (mov) => _eliminarMovimiento(app, mov),
                        ),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }

  // ── Arranque: desde cuándo se cuenta y con cuántas medias ──
  // Es el punto de partida del libro: se cuenta la cámara una vez y de ahí en
  // adelante manda lo que se vaya cargando.
  Future<void> _configurarArranque(AppProvider app) async {
    final actual = app.depositoConfig;
    var fecha = actual?.fechaInicio ?? DateTime.now();
    final novilloCtrl = TextEditingController(
      text: textoMiles(actual?.mediasNovillo ?? 0),
    );
    final cerdoCtrl = TextEditingController(
      text: textoMiles(actual?.mediasCerdo ?? 0),
    );
    // Los kilos del arranque son opcionales: si la cámara se cuenta sin
    // balanza, el arranque igual se guarda y el kilaje queda marcado como
    // incompleto en la tarjeta.
    final kgNovilloCtrl = TextEditingController(
      text: textoMiles(actual?.kgNovillo ?? 0),
    );
    final kgCerdoCtrl = TextEditingController(
      text: textoMiles(actual?.kgCerdo ?? 0),
    );

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Arranque del depósito'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Contá las medias que hay en la cámara. Desde esta '
                  'fecha en adelante manda lo que se cargue como entrada y '
                  'salida; lo anterior no se audita.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text('Desde el ${formatFecha(fecha)}'),
                  onPressed: () async {
                    final elegida = await showDatePicker(
                      context: ctx,
                      initialDate: fecha,
                      firstDate: DateTime(2026, 1, 1),
                      lastDate: DateTime.now(),
                    );
                    if (elegida != null) {
                      setStateDialog(() => fecha = elegida);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: novilloCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [MilesInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Medias de novillo en la cámara',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cerdoCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [MilesInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Medias de cerdo en la cámara',
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Si las pesaste, cargá los kilos de esas medias. Es lo que '
                  'le da kilaje al stock: sin esto la pantalla puede decir '
                  'cuántas medias hay, pero no cuánta carne.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: kgNovilloCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [MilesInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Kg de novillo (opcional)',
                    suffixText: 'kg',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: kgCerdoCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [MilesInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Kg de cerdo (opcional)',
                    suffixText: 'kg',
                  ),
                ),
              ],
            ),
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
      ),
    );

    if (guardar != true) return;

    final config = DepositoConfig(
      id: actual?.id,
      fechaInicio: fecha,
      mediasNovillo: parseNumero(novilloCtrl.text),
      mediasCerdo: parseNumero(cerdoCtrl.text),
      kgNovillo: parseNumero(kgNovilloCtrl.text),
      kgCerdo: parseNumero(kgCerdoCtrl.text),
      registradoPor: app.usuarioActual?.nombreCompleto,
    );
    final ok = await app.guardarDepositoConfig(config);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Arranque guardado'
            : app.error ?? 'No se pudo guardar el arranque'),
      ),
    );
  }

  // ── Entrada / Salida ──
  Future<void> _registrarMovimiento(AppProvider app, String clase) async {
    final esSalida = clase == DepositoMovimiento.claseSalida;
    var tipo = Proveedor.tipoNovillo;
    var fecha = DateTime.now();
    final mediasCtrl = TextEditingController();
    final obsCtrl = TextEditingController();
    final kgCtrls = <TextEditingController>[];

    final guardar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateSheet) {
          final medias = parseNumero(mediasCtrl.text);
          _sincronizarKg(kgCtrls, medias);
          return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  esSalida ? 'Salida de depósito' : 'Entrada a depósito',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  esSalida
                      ? 'Medias que salen de la cámara, por el motivo que '
                          'sea. El motivo va en la observación.'
                      : 'Medias que entran a la cámara: lo que llega del '
                          'proveedor, una devolución de un cliente, un '
                          'ajuste.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: Proveedor.tipoNovillo,
                      label: Text('Novillo'),
                    ),
                    ButtonSegment(
                      value: Proveedor.tipoCerdo,
                      label: Text('Cerdo'),
                    ),
                  ],
                  selected: {tipo},
                  onSelectionChanged: (s) =>
                      setStateSheet(() => tipo = s.first),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: mediasCtrl,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: const [MilesInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Cantidad de medias',
                  ),
                  onChanged: (_) => setStateSheet(() {}),
                ),
                _CamposKg(
                  controllers: kgCtrls,
                  medias: medias,
                  onChanged: () => setStateSheet(() {}),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(formatFecha(fecha)),
                  onPressed: () async {
                    final elegida = await showDatePicker(
                      context: ctx,
                      initialDate: fecha,
                      firstDate: DateTime(2026, 1, 1),
                      lastDate: DateTime.now(),
                    );
                    if (elegida != null) {
                      setStateSheet(() => fecha = elegida);
                    }
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: obsCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Observación',
                    hintText: esSalida
                        ? 'A quién se le llevó, quién la sacó...'
                        : 'De dónde viene',
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: medias <= 0
                        ? null
                        : () => Navigator.pop(ctx, true),
                    child: Text(
                      esSalida ? 'Registrar salida' : 'Registrar entrada',
                    ),
                  ),
                ),
              ],
            ),
          ),
          );
        },
      ),
    );

    if (guardar != true) return;

    final mov = DepositoMovimiento(
      tipo: tipo,
      clase: clase,
      medias: parseNumero(mediasCtrl.text),
      kgsPorMedia: _kgsCargados(kgCtrls),
      fecha: fecha,
      observacion: obsCtrl.text.trim(),
      registradoPor: app.usuarioActual?.nombreCompleto,
    );
    final ok = await app.registrarMovimientoDeposito(mov);
    if (!mounted) return;

    final stock = app.stockDeposito(tipo);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Quedan ${formatMediasConUnidad(stock.teorico)} de '
                '${stock.tipoLabel.toLowerCase()} en depósito'
            : app.error ?? 'No se pudo registrar el movimiento'),
      ),
    );
  }

  // ── Recuento físico ──
  Future<void> _registrarRecuento(
      AppProvider app, StockDeposito stock) async {
    final ctrl = TextEditingController();
    final kgCtrls = <TextEditingController>[];

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final medias = parseNumero(ctrl.text);
          _sincronizarKg(kgCtrls, medias);
          return AlertDialog(
            title: Text('Recuento de ${stock.tipoLabel.toLowerCase()}'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contá las medias de ${stock.tipoLabel.toLowerCase()} '
                      'que hay ahora en la cámara. El sistema espera '
                      '${formatMedias(stock.teorico)}.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: const [MilesInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Medias contadas',
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    _CamposKg(
                      controllers: kgCtrls,
                      medias: medias,
                      onChanged: () => setStateDialog(() {}),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar recuento'),
              ),
            ],
          );
        },
      ),
    );

    if (guardar != true) return;

    final mov = DepositoMovimiento(
      tipo: stock.tipo,
      clase: DepositoMovimiento.claseRecuento,
      medias: parseNumero(ctrl.text),
      kgsPorMedia: _kgsCargados(kgCtrls),
      observacion: 'Recuento físico',
      registradoPor: app.usuarioActual?.nombreCompleto,
    );
    final ok = await app.registrarMovimientoDeposito(mov);
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(app.error ?? 'No se pudo guardar el recuento'),
        ),
      );
      return;
    }

    final actualizado = app.stockDeposito(stock.tipo);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
            actualizado.cierra ? AppTheme.success : AppTheme.danger,
        content: Text(
          actualizado.cierra
              ? 'Los números dan redondos'
              : actualizado.faltan
                  ? 'Faltan ${formatMediasConUnidad(actualizado.faltantes)} '
                      'sin registrar'
                  : 'Hay ${formatMediasConUnidad(actualizado.sobrantes)} '
                      'de más sin registrar',
        ),
      ),
    );
  }

  // ── Baja con motivo obligatorio ──
  Future<void> _eliminarMovimiento(
      AppProvider app, DepositoMovimiento mov) async {
    final ctrl = TextEditingController();

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: Text('Eliminar ${mov.numeroFormateado}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${mov.claseLabel} de '
                '${formatMediasConUnidad(mov.medias)} de '
                '${mov.tipoLabel.toLowerCase()}'
                '${mov.tieneKg ? ' (${formatKg(mov.totalKg)})' : ''}, '
                '${formatFecha(mov.fecha)}.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motivo (obligatorio)',
                ),
                onChanged: (_) => setStateDialog(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.danger,
              ),
              onPressed: ctrl.text.trim().length < 3
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      ),
    );

    if (confirmar != true) return;

    final ok = await app.eliminarMovimientoDeposito(
      mov,
      observacion: ctrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Movimiento eliminado'
            : app.error ?? 'No se pudo eliminar'),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// Aviso de que falta el arranque
// ═══════════════════════════════════════════

class _SinConfigurar extends StatelessWidget {
  final VoidCallback onConfigurar;

  const _SinConfigurar({required this.onConfigurar});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.inventory_2_outlined,
                    color: AppTheme.primary, size: 22),
                SizedBox(width: 8),
                Text(
                  'Falta el arranque',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'El depósito necesita un punto de partida: contar las medias '
              'que hay hoy en la cámara y la fecha desde la que se empieza '
              'a contar. De ahí en adelante el sistema suma las entradas, '
              'resta las salidas y avisa si el recuento no da.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onConfigurar,
                icon: const Icon(Icons.tune),
                label: const Text('Configurar el arranque'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// Tarjeta de stock de un tipo
// ═══════════════════════════════════════════

class _TarjetaStock extends StatelessWidget {
  final StockDeposito stock;
  final VoidCallback onRecuento;

  const _TarjetaStock({
    required this.stock,
    required this.onRecuento,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stock.tipoLabel.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                Text(
                  formatMedias(stock.teorico),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'medias',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const Text(
              'Lo que debería haber en la cámara',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            // Los kilos contestan lo que las medias no pueden: cuánta carne
            // hay. Dos medias pueden diferenciarse en 40 kg.
            _KgEnCamara(stock: stock),
            const Divider(height: 20),

            // El desglose: de dónde sale ese número. Son tres líneas, que es
            // todo lo que el libro sabe.
            _Fila(
              label: 'Al arranque',
              valor: formatMedias(stock.inicial),
              kg: stock.kgInicial,
            ),
            _Fila(
              label: 'Entradas',
              valor: '+ ${formatMedias(stock.entradas)}',
              kg: stock.kgEntradas,
            ),
            _Fila(
              label: 'Salidas',
              valor: '− ${formatMedias(stock.salidas)}',
              kg: stock.kgSalidas,
            ),
            const Divider(height: 20),
            _Fila(
              label: stock.tieneRecuento
                  ? 'Contado el ${formatFecha(stock.fechaRecuento!)}'
                  : 'Todavía no se contó',
              valor: stock.tieneRecuento
                  ? formatMedias(stock.recuento!)
                  : '—',
              destacado: true,
            ),
            // Los kilos del recuento son los únicos que se pesaron de
            // verdad: el kilaje del libro puede estar incompleto, así que
            // este es el dato duro.
            if (stock.kgRecuento > 0)
              _Fila(
                label: 'Kg pesados en ese recuento',
                valor: formatKg(stock.kgRecuento),
              ),
            const SizedBox(height: 10),
            _Veredicto(stock: stock),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRecuento,
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: const Text('Registrar recuento'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Los kilos de lo que debería estar en la cámara (v19.9).
///
/// Hasta v19.8 el módulo pedía los kilos de cada media pero no los mostraba
/// nunca de vuelta: se cargaban y desaparecían. Acá vuelven, con la misma
/// cuenta que las medias pero en peso.
///
/// El kilaje puede estar INCOMPLETO (un movimiento que nadie pesó, un
/// arranque sin balanza) y se dice explícitamente: un número de kilos que
/// parece exacto y no lo es es peor que no mostrarlo.
class _KgEnCamara extends StatelessWidget {
  final StockDeposito stock;

  const _KgEnCamara({required this.stock});

  @override
  Widget build(BuildContext context) {
    if (!stock.tieneKg && !stock.kgIncompleto) return const SizedBox.shrink();

    final falta = stock.kgIncompleto
        ? 'faltan pesar ${formatMediasConUnidad(stock.mediasSinPesar)}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        stock.tieneKg
            ? '${formatKg(stock.kgTeorico)}${falta.isEmpty ? '' : ' · $falta'}'
            : 'Sin kilos cargados: $falta',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: stock.kgIncompleto
              ? AppTheme.warning
              : AppTheme.textPrimary,
        ),
      ),
    );
  }
}

/// El cartel que responde la pregunta de Joaco: ¿dan los números?
class _Veredicto extends StatelessWidget {
  final StockDeposito stock;

  const _Veredicto({required this.stock});

  @override
  Widget build(BuildContext context) {
    if (!stock.tieneRecuento) {
      return const _Cartel(
        color: AppTheme.info,
        fondo: AppTheme.infoBg,
        icono: Icons.help_outline,
        titulo: 'Sin recuento',
        detalle:
            'Contá las medias que hay en la cámara para que el sistema '
            'pueda comparar.',
      );
    }

    if (stock.cierra) {
      return const _Cartel(
        color: AppTheme.success,
        fondo: AppTheme.successBg,
        icono: Icons.check_circle_outline,
        titulo: 'Los números dan redondos',
        detalle: 'Lo que dice el libro es lo que hay en la cámara.',
      );
    }

    if (stock.faltan) {
      return _Cartel(
        color: AppTheme.danger,
        fondo: AppTheme.dangerBg,
        icono: Icons.error_outline,
        titulo:
            'Faltan ${formatMediasConUnidad(stock.faltantes)} sin registrar',
        detalle:
            'Se contó menos de lo que dice el libro: salieron de la cámara '
            'y nadie las registró. Cargá la salida que falta y anotá en la '
            'observación a dónde fueron.',
      );
    }

    return _Cartel(
      color: AppTheme.warning,
      fondo: AppTheme.warningBg,
      icono: Icons.warning_amber_outlined,
      titulo:
          'Hay ${formatMediasConUnidad(stock.sobrantes)} de más en la cámara',
      detalle:
          'Se contó más de lo que dice el libro. Puede faltar cargar una '
          'entrada, o sobrar una salida cargada de más.',
    );
  }
}

/// Los campos de kg, uno por media, igual que el formulario de nota de
/// pedido. Aparecen y desaparecen solos a medida que se tipea la cantidad.
///
/// Son OPCIONALES a propósito: el pie dice cuántas faltan pesar pero nada
/// bloquea el guardado. Si el campo frenara a la cajera cuando no tiene la
/// balanza a mano, no registraría la salida, que es el agujero que este
/// módulo vino a tapar.
class _CamposKg extends StatelessWidget {
  final List<TextEditingController> controllers;
  final double medias;
  final VoidCallback onChanged;

  const _CamposKg({
    required this.controllers,
    required this.medias,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (controllers.isEmpty) return const SizedBox.shrink();

    final cargados = _kgsCargados(controllers);
    final total = cargados.fold<double>(0, (t, kg) => t + kg);
    final faltan = controllers.length - cargados.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const Text(
          'Kg de cada media (opcional)',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: controllers.asMap().entries.map((e) {
            return SizedBox(
              width: 90,
              child: TextField(
                controller: e.value,
                decoration: InputDecoration(
                  labelText: 'Media ${e.key + 1}',
                  isDense: true,
                  suffixText: 'kg',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: const [MilesInputFormatter()],
                onChanged: (_) => onChanged(),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text(
          total <= 0
              ? 'Sin pesar todavía'
              : 'Total ${formatKg(total)}'
                  '${faltan > 0 ? ' · faltan $faltan por pesar' : ''}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: faltan > 0 ? AppTheme.warning : AppTheme.textSecondary,
          ),
        ),
        if (medias.ceil() > _maxCamposKg)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Son demasiadas medias para pesar una por una: se muestran '
              'los primeros $_maxCamposKg campos.',
              style: TextStyle(fontSize: 11, color: AppTheme.warning),
            ),
          ),
      ],
    );
  }
}

class _Cartel extends StatelessWidget {
  final Color color;
  final Color fondo;
  final IconData icono;
  final String titulo;
  final String detalle;

  const _Cartel({
    required this.color,
    required this.fondo,
    required this.icono,
    required this.titulo,
    required this.detalle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
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

// ═══════════════════════════════════════════
// Los dos botones del circuito
// ═══════════════════════════════════════════

class _BotonesMovimiento extends StatelessWidget {
  final VoidCallback onEntrada;
  final VoidCallback onSalida;

  const _BotonesMovimiento({
    required this.onEntrada,
    required this.onSalida,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: AppTheme.success,
            ),
            onPressed: onEntrada,
            icon: const Icon(Icons.arrow_downward),
            label: const Text('Entrada'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: onSalida,
            icon: const Icon(Icons.arrow_upward),
            label: const Text('Salida'),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════
// Historial
// ═══════════════════════════════════════════

class _Historial extends StatelessWidget {
  final List<DepositoMovimiento> movimientos;
  final void Function(DepositoMovimiento) onTap;

  const _Historial({required this.movimientos, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (movimientos.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: Text(
              'Todavía no hay movimientos cargados',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MOVIMIENTOS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tocá uno para eliminarlo (pide motivo).',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            for (final mov in movimientos)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  mov.esRecuento
                      ? Icons.fact_check_outlined
                      : mov.esEntrada
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                  size: 20,
                  color: mov.esRecuento
                      ? AppTheme.info
                      : mov.esEntrada
                          ? AppTheme.success
                          : AppTheme.primary,
                ),
                title: Text(
                  '${mov.claseLabel} · ${formatMedias(mov.medias)} de '
                  '${mov.tipoLabel.toLowerCase()}'
                  '${mov.tieneKg ? ' · ${formatKg(mov.totalKg)}' : ''}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  '${mov.numeroFormateado} · ${formatFecha(mov.fecha)}'
                  '${mov.mediasSinPesar > 0 ? ' · ${mov.mediasSinPesar} sin pesar' : ''}'
                  '${mov.observacion.trim().isEmpty ? '' : '\n${mov.observacion.trim()}'}',
                  style: const TextStyle(fontSize: 11),
                ),
                isThreeLine: mov.observacion.trim().isNotEmpty,
                onTap: () => onTap(mov),
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

  /// Los kilos de esa línea. Van abajo del texto y no en una columna aparte:
  /// en el celular una tercera columna deja los números ilegibles. Cuando es
  /// 0 no se muestra nada, porque 0 kg acá significa "nadie lo pesó" y no
  /// "no pesa nada".
  final double kg;

  const _Fila({
    required this.label,
    required this.valor,
    this.destacado = false,
    this.kg = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (kg > 0)
                  Text(
                    formatKg(kg),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              fontSize: 13,
              fontWeight: destacado ? FontWeight.w700 : FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
