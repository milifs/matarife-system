// ============================================================
// PANTALLA DE REPARTO - Logística semanal de medias
// ============================================================
// Dos tablas por día: una de CARNE (novillo) y otra de CERDO. Cada una
// con su TOTAL MEDIAS (a mano), sus clientes y su SOBRANTE (calculado).
// Se ve una por vez, con su propio selector arriba, igual que el día:
// la carne y el cerdo los reparte gente distinta y son dos listas.
// Un día por lista: jueves, viernes y sábado, navegable por semana.
// No involucra plata, saldos ni remitos. Exporta UN PDF POR TABLA, que es
// lo que recibe cada repartidor.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/reparto_service.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';

class RepartoScreen extends StatefulWidget {
  const RepartoScreen({super.key});

  @override
  State<RepartoScreen> createState() => _RepartoScreenState();
}

class _RepartoScreenState extends State<RepartoScreen> {
  final _db = DatabaseService();

  late DateTime _semana; // lunes de la semana
  String _dia = 'jueves';

  /// Tabla que se está mirando. Las dos viven en memoria y se guardan
  /// juntas (son la misma lista del día); esto es solo cuál se muestra.
  String _tipo = tipoRepartoCarne;

  bool _cargando = true;
  bool _guardando = false;
  // La lista mostrada se sembró de la semana anterior y todavía no se guardó
  // para esta semana. Sirve para el banner y para no auto-guardar una
  // plantilla que el usuario no llegó a tocar.
  bool _precargado = false;

  // Una tabla por mercadería: su TOTAL MEDIAS y sus filas de clientes.
  final Map<String, TextEditingController> _totalCtrl = {
    tipoRepartoCarne: TextEditingController(),
    tipoRepartoCerdo: TextEditingController(),
  };
  final Map<String, List<_Fila>> _filas = {
    tipoRepartoCarne: [],
    tipoRepartoCerdo: [],
  };

  /// Encabezados de las columnas agregadas a mano, por tabla. El índice es
  /// la posición de la columna, y es lo que ata cada número de las filas a
  /// su encabezado.
  final Map<String, List<TextEditingController>> _columnas = {
    tipoRepartoCarne: [],
    tipoRepartoCerdo: [],
  };

  final _notasCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    final lunes = hoy.subtract(Duration(days: hoy.weekday - 1));
    _semana = DateTime(lunes.year, lunes.month, lunes.day);
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _totalCtrl.values) {
      c.dispose();
    }
    _notasCtrl.dispose();
    for (final c in _columnas.values.expand((l) => l)) {
      c.dispose();
    }
    for (final f in _todasLasFilas) {
      f.dispose();
    }
    super.dispose();
  }

  Iterable<_Fila> get _todasLasFilas =>
      _filas.values.expand((filas) => filas);

  bool get _hayContenido =>
      _todasLasFilas.isNotEmpty ||
      _totalCtrl.values.any((c) => c.text.trim().isNotEmpty) ||
      _notasCtrl.text.trim().isNotEmpty;

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    // Si la semana todavía no tiene lista, viene sembrada con la de la semana
    // anterior (misma lógica que usa el asistente de reparto).
    final res = await _db.getRepartoListaOPlantilla(_semana, _dia);
    final lista = res.lista;

    for (final f in _todasLasFilas) {
      f.dispose();
    }
    for (final tipo in _filas.keys) {
      _filas[tipo] = [];
    }
    for (final tipo in _columnas.keys) {
      for (final c in _columnas[tipo]!) {
        c.dispose();
      }
      _columnas[tipo] = [
        for (final nombre in lista.columnasDe(tipo))
          TextEditingController(text: nombre),
      ];
    }
    _precargado = res.precargado;

    _totalCtrl[tipoRepartoCarne]!.text =
        lista.totalMediasCarne == 0 ? '' : '${lista.totalMediasCarne}';
    _totalCtrl[tipoRepartoCerdo]!.text =
        lista.totalMediasCerdo == 0 ? '' : '${lista.totalMediasCerdo}';
    _notasCtrl.text = lista.notas;
    for (final it in lista.items) {
      _filas[it.tipo]?.add(_Fila(
        clienteId: it.clienteId,
        medias: it.medias,
        sucursal: it.sucursal,
        extras: it.extras,
        columnas: _columnas[it.tipo]?.length ?? 0,
      ));
    }

    if (mounted) setState(() => _cargando = false);
  }

  RepartoLista _construirLista() {
    final items = <RepartoItem>[];
    for (final tipo in tiposReparto) {
      for (final f in _filas[tipo]!) {
        items.add(RepartoItem(
          clienteId: f.clienteId,
          tipo: tipo,
          medias: f.cantidad,
          extras: f.extras,
          sucursal: f.sucursalCtrl.text.trim(),
          orden: items.length,
        ));
      }
    }
    return RepartoLista(
      columnasExtra: {
        for (final tipo in tiposReparto)
          if (_columnas[tipo]!.isNotEmpty)
            tipo: [for (final c in _columnas[tipo]!) c.text.trim()],
      },
      semanaInicio: _semana,
      dia: _dia,
      totalMediasCarne: _total(tipoRepartoCarne),
      totalMediasCerdo: _total(tipoRepartoCerdo),
      notas: _notasCtrl.text.trim(),
      items: items,
    );
  }

  int _total(String tipo) =>
      int.tryParse(_totalCtrl[tipo]!.text.trim()) ?? 0;

  int _repartido(String tipo) =>
      _filas[tipo]!.fold(0, (s, f) => s + f.cantidad);

  int _sobrante(String tipo) => _total(tipo) - _repartido(tipo);

  int _sumaExtra(String tipo, int columna) => _filas[tipo]!.fold(
      0,
      (s, f) => s +
          (columna < f.extraCtrls.length
              ? int.tryParse(f.extraCtrls[columna].text.trim()) ?? 0
              : 0));

  // Al tocar cualquier campo, la plantilla precargada deja de serlo: pasa a
  // ser la lista real de esta semana (se auto-guardará al navegar).
  void _marcarModificado() {
    if (_precargado) setState(() => _precargado = false);
  }

  Future<void> _persistir({bool silencioso = false}) async {
    setState(() => _guardando = true);
    try {
      await _db.guardarReparto(_construirLista());
      _precargado = false;
      if (!silencioso && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reparto guardado'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo guardar: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _cambiarSemana(int deltaSemanas) async {
    // Una plantilla precargada sin tocar no se guarda: evita crear listas
    // fantasma solo por navegar entre semanas.
    if (_hayContenido && !_precargado) await _persistir(silencioso: true);
    setState(() {
      _semana = _semana.add(Duration(days: 7 * deltaSemanas));
    });
    await _cargar();
  }

  Future<void> _cambiarDia(String dia) async {
    if (dia == _dia) return;
    if (_hayContenido && !_precargado) await _persistir(silencioso: true);
    setState(() => _dia = dia);
    await _cargar();
  }

  bool get _esSemanaActual {
    final hoy = DateTime.now();
    final lunesHoy = DateTime(hoy.year, hoy.month, hoy.day)
        .subtract(Duration(days: hoy.weekday - 1));
    return _semana.isAtSameMomentAs(lunesHoy);
  }

  Future<void> _agregarCliente(String tipo) async {
    final app = context.read<AppProvider>();
    // Se permite agregar el mismo cliente más de una vez (una fila por
    // sucursal), así que no se excluyen los ya agregados.
    final elegido = await showModalBottomSheet<Cliente>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SelectorCliente(
        clientes: app.clientes,
        titulo: 'Agregar cliente a ${labelTipoReparto(tipo)}',
      ),
    );

    if (elegido == null) return;
    setState(() {
      // Con las columnas que la tabla YA tiene: sin esto la fila nueva nace
      // sin esos campos y la celda aparece vacía y no se puede tipear.
      _filas[tipo]!.add(_Fila(
        clienteId: elegido.id,
        columnas: _columnas[tipo]!.length,
      ));
      _precargado = false;
    });
  }

  void _agregarColumna(String tipo) {
    if (_columnas[tipo]!.length >= maxColumnasExtra) return;
    setState(() {
      _columnas[tipo]!.add(TextEditingController());
      for (final f in _filas[tipo]!) {
        f.ajustarColumnas(_columnas[tipo]!.length);
      }
      _precargado = false;
    });
  }

  void _quitarColumna(String tipo, int i) {
    setState(() {
      _columnas[tipo]!.removeAt(i).dispose();
      for (final f in _filas[tipo]!) {
        f.quitarColumna(i);
      }
      _precargado = false;
    });
  }

  /// La celda del encabezado mide 56: no entra un campo de texto con su
  /// botón de borrar al lado. Se toca y se edita acá.
  Future<void> _editarColumna(String tipo, int i) async {
    final ctrl = _columnas[tipo]![i];
    final previo = ctrl.text;
    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Columna'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 14,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Encabezado',
            hintText: 'Ej: Pierna, Grasa',
            counterText: '',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, 'guardar'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'quitar'),
            child: const Text('Quitar columna',
                style: TextStyle(color: AppTheme.danger)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancelar'),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'guardar'),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accion == 'quitar') {
      final nombre = ctrl.text.trim();
      final ok = await _confirmarQuitarColumna(tipo, i, nombre);
      if (ok) _quitarColumna(tipo, i);
      return;
    }
    if (accion == 'guardar') {
      _marcarModificado();
      setState(() {});
    } else {
      // Cancelar tiene que deshacer lo tipeado: el controller es el mismo
      // que vive en la grilla, así que el diálogo lo edita en vivo.
      ctrl.text = previo;
    }
  }

  Future<bool> _confirmarQuitarColumna(
      String tipo, int i, String nombre) async {
    final cargadas =
        _filas[tipo]!.where((f) => f.extras.length > i && f.extras[i] > 0);
    if (cargadas.isEmpty) return true;
    // Quitar la columna se lleva los números de todos los clientes, así que
    // si hay algo cargado hay que preguntar.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Quitar ${nombre.isEmpty ? "la columna" : nombre}'),
        content: Text(
            'Hay ${cargadas.length} ${cargadas.length == 1 ? "cliente" : "clientes"} '
            'con cantidad cargada en esta columna. Se van a borrar.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _generarPdf(String tipo) async {
    final app = context.read<AppProvider>();
    // Persistimos antes para que el PDF y la base queden alineados.
    await _persistir(silencioso: true);
    try {
      await RepartoService.generarYCompartir(
        lista: _construirLista(),
        clientes: app.clientes,
        tipo: tipo,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo generar el PDF: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de reparto'),
        actions: [
          IconButton(
            tooltip: 'Guardar',
            onPressed: _guardando ? null : () => _persistir(),
            icon: _guardando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
          ),
          // Un PDF por tabla: cada repartidor se lleva el suyo.
          PopupMenuButton<String>(
            tooltip: 'PDF para el repartidor',
            enabled: !_guardando,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onSelected: _generarPdf,
            itemBuilder: (_) => [
              for (final t in tiposReparto)
                PopupMenuItem(
                  value: t,
                  child: Text('PDF de ${labelTipoReparto(t)}'),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _barraSemana(),
          _selectorDia(),
          _selectorTipo(),
          const Divider(height: 1),
          if (_precargado && !_cargando) _bannerPrecargado(),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                    children: [
                      _tabla(app, _tipo),
                      const SizedBox(height: 16),
                      // NOTAS: son del día, así que se ven y se editan desde
                      // las dos tablas. Es el mismo texto.
                      TextField(
                        controller: _notasCtrl,
                        minLines: 2,
                        maxLines: 4,
                        onChanged: (_) => _marcarModificado(),
                        decoration: const InputDecoration(
                          labelText: 'Notas sueltas del día',
                          hintText: 'Ej: buscar morcillas de La Florida',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: _cargando
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _agregarCliente(_tipo),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Agregar cliente'),
            ),
    );
  }

  Widget _bannerPrecargado() {
    return Container(
      width: double.infinity,
      color: AppTheme.infoBg,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: const Row(
        children: [
          Icon(Icons.history, size: 18, color: AppTheme.textSecondary),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Precargado de la semana pasada. Revisá y tocá guardar para '
              'confirmar la lista de esta semana.',
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barraSemana() {
    return Container(
      color: AppTheme.card,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _cambiarSemana(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  formatRangoSemana(_semana),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (_esSemanaActual)
                  const Text('Semana actual',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          IconButton(
            onPressed: _esSemanaActual ? null : () => _cambiarSemana(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  /// Selector de tabla, con el mismo gesto que el del día. Cambiar de tabla
  /// no toca la base: las dos son la misma lista y se guardan juntas.
  Widget _selectorTipo() {
    return Container(
      color: AppTheme.card,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          for (final t in tiposReparto)
            ButtonSegment(
              value: t,
              icon: Icon(t == tipoRepartoCerdo
                  ? Icons.savings_outlined
                  : Icons.kebab_dining),
              label: Text(t == tipoRepartoCerdo ? 'Cerdo' : 'Carne'),
            ),
        ],
        selected: {_tipo},
        onSelectionChanged: (s) => setState(() => _tipo = s.first),
      ),
    );
  }

  Widget _selectorDia() {
    return Container(
      color: AppTheme.card,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          for (final d in diasReparto)
            ButtonSegment(value: d, label: Text(labelDiaReparto(d))),
        ],
        selected: {_dia},
        onSelectionChanged: (s) => _cambiarDia(s.first),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // Una tabla (CARNE o CERDO)
  // ─────────────────────────────────────────────
  /// Las filas como se ven, A→Z. Lo usan la grilla y el salto con las
  /// flechas: si no fuera el mismo orden, la flecha bajaría a otra fila.
  List<_Fila> _filasOrdenadas(AppProvider app, String tipo) =>
      [..._filas[tipo]!]..sort((a, b) {
          final na = app.clientePorId(a.clienteId)?.nombreRazonSocial ?? '';
          final nb = app.clientePorId(b.clienteId)?.nombreRazonSocial ?? '';
          return compararNombres(na, nb);
        });

  /// Baja o sube una celda, en la misma columna. Es para cargar la lista de
  /// corrido: el tabulador pasa por la sucursal y por la cruz de quitar.
  void _moverFoco(
      AppProvider app, String tipo, _Fila desde, int columna, int delta) {
    final filas = _filasOrdenadas(app, tipo);
    final i = filas.indexOf(desde);
    if (i < 0) return;
    final destino = i + delta;
    if (destino < 0 || destino >= filas.length) return;

    final foco = filas[destino].focoDe(columna);
    if (foco == null) return;
    foco.requestFocus();

    // Deja el número seleccionado: así se tipea encima sin borrar antes,
    // que es como se carga una planilla.
    final ctrl = filas[destino].controllerDe(columna);
    if (ctrl != null) {
      ctrl.selection =
          TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
    }
  }

  Widget _tabla(AppProvider app, String tipo) {
    final filas = _filasOrdenadas(app, tipo);
    final esCerdo = tipo == tipoRepartoCerdo;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gridLine),
      ),
      // Las líneas de la grilla llegan hasta el borde de la tarjeta, así que
      // hay que recortarlas para que no se pasen de las esquinas redondeadas.
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Título de la tabla
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: esCerdo
                  ? AppTheme.warningBg
                  : AppTheme.primary.withValues(alpha: 0.08),
              border: const Border(
                  bottom: BorderSide(color: AppTheme.gridLine)),
            ),
            child: Row(
              children: [
                Icon(esCerdo ? Icons.savings_outlined : Icons.kebab_dining,
                    size: 18,
                    color: esCerdo ? AppTheme.warning : AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    esCerdo ? 'CERDO' : 'CARNE (NOVILLO)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: esCerdo ? AppTheme.warning : AppTheme.primary,
                    ),
                  ),
                ),
                Text(
                  '${filas.length} ${filas.length == 1 ? "cliente" : "clientes"}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary),
                ),
                // Hasta dos columnas más, para lo que se vende suelto y no
                // es una media (una pierna, grasa).
                IconButton(
                  tooltip: _columnas[tipo]!.length >= maxColumnasExtra
                      ? 'Ya tiene las $maxColumnasExtra columnas'
                      : 'Agregar columna',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _columnas[tipo]!.length >= maxColumnasExtra
                      ? null
                      : () => _agregarColumna(tipo),
                  icon: const Icon(Icons.add_box_outlined, size: 22),
                ),
              ],
            ),
          ),
          _filaHeader(tipo),
          _filaTotal(tipo),
          if (filas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text('Todavía no hay clientes en esta tabla',
                  style: TextStyle(
                      fontSize: 13, color: AppTheme.textSecondary)),
            )
          else
            for (final fila in filas)
              _FilaCliente(
                key: ObjectKey(fila),
                fila: fila,
                columnas: _columnas[tipo]!.length,
                nombre: app.clientePorId(fila.clienteId)?.nombreRazonSocial ??
                    '(cliente eliminado)',
                onCambio: () {
                  _marcarModificado();
                  setState(() {});
                },
                onQuitar: () {
                  setState(() {
                    fila.dispose();
                    _filas[tipo]!.remove(fila);
                    _precargado = false;
                  });
                },
                onFlecha: (columna, delta) =>
                    _moverFoco(app, tipo, fila, columna, delta),
              ),
          _filaSobrante(tipo, _sobrante(tipo)),
        ],
      ),
    );
  }

  Widget _filaHeader(String tipo) {
    return _filaGrilla(
      fondo: AppTheme.background,
      izquierda: const Text('CLIENTE',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      celdas: [
        const Text('MEDIAS',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        for (var i = 0; i < _columnas[tipo]!.length; i++)
          _encabezadoColumna(tipo, i),
      ],
    );
  }

  /// Encabezado de una columna agregada a mano. Se toca para renombrarla o
  /// sacarla.
  Widget _encabezadoColumna(String tipo, int i) {
    final nombre = _columnas[tipo]![i].text.trim();
    return InkWell(
      onTap: () => _editarColumna(tipo, i),
      child: Tooltip(
        message: 'Tocá para renombrar o quitar',
        child: Text(
          nombre.isEmpty ? 'SIN NOMBRE' : nombre.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: nombre.isEmpty ? AppTheme.textHint : AppTheme.info,
          ),
        ),
      ),
    );
  }

  Widget _filaTotal(String tipo) {
    return _filaGrilla(
      fondo: AppTheme.infoBg,
      izquierda: const Text('TOTAL',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      celdas: [
        _campoNumero(_totalCtrl[tipo]!),
        // Las columnas extra no tienen un total que cargar a mano: no hay
        // stock de "grasa" contra el cual contarlas. Se muestra la suma de
        // lo repartido, y por eso tampoco tienen sobrante.
        for (var i = 0; i < _columnas[tipo]!.length; i++)
          Text(
            '${_sumaExtra(tipo, i)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.textSecondary),
          ),
      ],
    );
  }

  Widget _filaSobrante(String tipo, int valor) {
    return _filaGrilla(
      fondo: AppTheme.infoBg,
      ultima: true,
      izquierda: const Text('SOBRANTE DEPÓSITO',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
      celdas: [
        Text(
          '$valor',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valor < 0 ? AppTheme.danger : AppTheme.textPrimary,
          ),
        ),
        for (var i = 0; i < _columnas[tipo]!.length; i++)
          const Text('—',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppTheme.textHint)),
      ],
    );
  }

  Widget _campoNumero(TextEditingController ctrl) => _campoMedias(
        ctrl: ctrl,
        onCambio: () {
          _marcarModificado();
          setState(() {});
        },
      );
}

// ─────────────────────────────────────────────
// La grilla
// ─────────────────────────────────────────────
// Todas las filas (encabezado, total, clientes y sobrante) se arman con
// este helper, que es lo que hace que las líneas verticales queden
// alineadas de punta a punta. Si una fila se dibujara por su cuenta, la
// columna de medias se correría y la grilla dejaría de leerse.

const double _anchoCelda = 56;
const double _anchoAccion = 40;

Widget _filaGrilla({
  required Widget izquierda,
  required List<Widget> celdas,
  Widget? derecha,
  Color? fondo,
  bool ultima = false,
}) {
  const linea = BorderSide(color: AppTheme.gridLine);
  return Container(
    decoration: BoxDecoration(
      color: fondo,
      border: Border(bottom: ultima ? BorderSide.none : linea),
    ),
    // Estira las celdas al alto de la fila: sin esto las líneas verticales
    // salen cortadas en las filas más altas (las que tienen sucursal).
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              child: Align(
                  alignment: Alignment.centerLeft, child: izquierda),
            ),
          ),
          for (final celda in celdas)
            Container(
              width: _anchoCelda,
              decoration: const BoxDecoration(border: Border(left: linea)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
              child: Center(child: celda),
            ),
          Container(
            width: _anchoAccion,
            decoration: const BoxDecoration(border: Border(left: linea)),
            child: Center(child: derecha ?? const SizedBox.shrink()),
          ),
        ],
      ),
    ),
  );
}

/// El campo de medias de cualquier fila. Sin ancho propio: se lo da la
/// celda de la grilla.
Widget _campoMedias({
  required TextEditingController ctrl,
  required VoidCallback onCambio,
  FocusNode? focusNode,
  void Function(int delta)? onFlechaVertical,
}) {
  final campo = TextField(
    controller: ctrl,
    focusNode: focusNode,
    textAlign: TextAlign.center,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    onChanged: (_) => onCambio(),
    decoration: const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      hintText: '0',
    ),
  );
  if (onFlechaVertical == null) return campo;

  // Se engancha ARRIBA del campo: la tecla sube desde el que tiene el foco
  // hacia sus padres, así que llega acá antes que a los atajos de edición
  // de texto. En un campo de una línea la flecha vertical no hace nada
  // útil, así que no le sacamos nada al usuario.
  return Focus(
    canRequestFocus: false,
    onKeyEvent: (_, evento) {
      if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      if (evento.logicalKey == LogicalKeyboardKey.arrowDown) {
        onFlechaVertical(1);
        return KeyEventResult.handled;
      }
      if (evento.logicalKey == LogicalKeyboardKey.arrowUp) {
        onFlechaVertical(-1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: campo,
  );
}

// ─────────────────────────────────────────────
// Fila de cliente (con resaltado al pasar el mouse)
// ─────────────────────────────────────────────
// Es un widget aparte y no un método de la pantalla por el hover: así el
// mouse repinta UN renglón y no la lista entera en cada movimiento.
class _FilaCliente extends StatefulWidget {
  final _Fila fila;
  final String nombre;
  final int columnas;
  final VoidCallback onCambio;
  final VoidCallback onQuitar;

  /// Flecha arriba / abajo en una celda: (columna, -1 o 1).
  final void Function(int columna, int delta) onFlecha;

  const _FilaCliente({
    super.key,
    required this.fila,
    required this.nombre,
    required this.columnas,
    required this.onCambio,
    required this.onQuitar,
    required this.onFlecha,
  });

  @override
  State<_FilaCliente> createState() => _FilaClienteState();
}

class _FilaClienteState extends State<_FilaCliente> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: _filaGrilla(
        fondo: _hover ? AppTheme.gridHover : null,
        izquierda: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.nombre,
              style: TextStyle(
                fontSize: 14,
                // El nombre se pinta al señalarlo: en una lista larga es lo
                // que dice qué renglón se está por tocar. El grosor NO
                // cambia, para que el texto no se mueva solo.
                color: _hover ? AppTheme.primary : AppTheme.textPrimary,
              ),
            ),
            TextField(
              controller: widget.fila.sucursalCtrl,
              maxLength: 40,
              onChanged: (_) => widget.onCambio(),
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                counterText: '',
                contentPadding:
                    EdgeInsets.symmetric(vertical: 2, horizontal: 0),
                hintText: 'Sucursal (opcional)',
                hintStyle:
                    TextStyle(fontSize: 12, color: AppTheme.textHint),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ],
        ),
        celdas: [
          _campoMedias(
            ctrl: widget.fila.mediasCtrl,
            focusNode: widget.fila.mediasFocus,
            onCambio: widget.onCambio,
            onFlechaVertical: (delta) => widget.onFlecha(0, delta),
          ),
          for (var i = 0; i < widget.columnas; i++)
            if (i < widget.fila.extraCtrls.length)
              _campoMedias(
                ctrl: widget.fila.extraCtrls[i],
                focusNode: widget.fila.extraFocus[i],
                onCambio: widget.onCambio,
                onFlechaVertical: (delta) => widget.onFlecha(i + 1, delta),
              )
            else
              const SizedBox.shrink(),
        ],
        derecha: IconButton(
          tooltip: 'Quitar',
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.close, size: 18, color: AppTheme.textHint),
          onPressed: widget.onQuitar,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Fila editable en memoria (una mercadería, un cliente)
// ─────────────────────────────────────────────
class _Fila {
  final String clienteId;
  final TextEditingController mediasCtrl;
  final TextEditingController sucursalCtrl;

  /// Un campo por columna extra de su tabla, en el mismo orden.
  final List<TextEditingController> extraCtrls;

  /// El foco de cada celda numérica, para poder bajar y subir con las
  /// flechas. El índice 0 es la de medias; de ahí en más, las extra.
  final FocusNode mediasFocus = FocusNode();
  final List<FocusNode> extraFocus = [];

  _Fila({
    required this.clienteId,
    int medias = 0,
    String sucursal = '',
    List<int> extras = const [],
    int columnas = 0,
  })  : mediasCtrl =
            TextEditingController(text: medias == 0 ? '' : '$medias'),
        sucursalCtrl = TextEditingController(text: sucursal),
        extraCtrls = [
          for (var i = 0; i < columnas; i++)
            TextEditingController(
                text: (i < extras.length && extras[i] != 0)
                    ? '${extras[i]}'
                    : ''),
        ] {
    for (var i = 0; i < columnas; i++) {
      extraFocus.add(FocusNode());
    }
  }

  /// El foco de la celda [columna]: 0 es medias, 1 en adelante las extra.
  FocusNode? focoDe(int columna) {
    if (columna == 0) return mediasFocus;
    final i = columna - 1;
    return i < extraFocus.length ? extraFocus[i] : null;
  }

  /// El controller de la celda [columna], con el mismo criterio.
  TextEditingController? controllerDe(int columna) {
    if (columna == 0) return mediasCtrl;
    final i = columna - 1;
    return i < extraCtrls.length ? extraCtrls[i] : null;
  }

  int get cantidad => int.tryParse(mediasCtrl.text.trim()) ?? 0;

  List<int> get extras =>
      [for (final c in extraCtrls) int.tryParse(c.text.trim()) ?? 0];

  /// Suma o saca campos cuando la tabla gana o pierde una columna.
  void ajustarColumnas(int columnas) {
    while (extraCtrls.length > columnas) {
      extraCtrls.removeLast().dispose();
      extraFocus.removeLast().dispose();
    }
    while (extraCtrls.length < columnas) {
      extraCtrls.add(TextEditingController());
      extraFocus.add(FocusNode());
    }
  }

  /// Saca el campo de una columna que se quitó del medio.
  void quitarColumna(int i) {
    if (i >= 0 && i < extraCtrls.length) extraCtrls.removeAt(i).dispose();
    if (i >= 0 && i < extraFocus.length) extraFocus.removeAt(i).dispose();
  }

  void dispose() {
    mediasCtrl.dispose();
    sucursalCtrl.dispose();
    mediasFocus.dispose();
    for (final c in extraCtrls) {
      c.dispose();
    }
    for (final f in extraFocus) {
      f.dispose();
    }
  }
}

// ─────────────────────────────────────────────
// Selector de cliente (búsqueda + lista A→Z)
// ─────────────────────────────────────────────
class _SelectorCliente extends StatefulWidget {
  final List<Cliente> clientes;
  final String titulo;
  const _SelectorCliente({required this.clientes, required this.titulo});

  @override
  State<_SelectorCliente> createState() => _SelectorClienteState();
}

class _SelectorClienteState extends State<_SelectorCliente> {
  String _busqueda = '';

  @override
  Widget build(BuildContext context) {
    final filtro = normalizarBusqueda(_busqueda);
    final lista = widget.clientes
        .where((c) =>
            filtro.isEmpty ||
            normalizarBusqueda(c.nombreRazonSocial).contains(filtro))
        .toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.titulo,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Buscar cliente',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _busqueda = v),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: lista.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('Sin clientes disponibles',
                          style:
                              TextStyle(color: AppTheme.textSecondary)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: lista.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = lista[i];
                      return ListTile(
                        dense: true,
                        title: Text(c.nombreRazonSocial),
                        onTap: () => Navigator.pop(context, c),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
