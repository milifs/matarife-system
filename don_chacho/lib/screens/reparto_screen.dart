// ============================================================
// PANTALLA DE REPARTO - Logística semanal de medias
// ============================================================
// Dos tablas por día: una de CARNE (novillo) y otra de CERDO. Cada una
// con su TOTAL MEDIAS (a mano), sus clientes y su SOBRANTE (calculado).
// Un día por lista: jueves, viernes y sábado, navegable por semana.
// No involucra plata, saldos ni remitos. Exporta PDF para el repartidor.
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
          sucursal: f.sucursalCtrl.text.trim(),
          orden: items.length,
        ));
      }
    }
    return RepartoLista(
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
      _filas[tipo]!.add(_Fila(clienteId: elegido.id));
      _precargado = false;
    });
  }

  Future<void> _generarPdf() async {
    final app = context.read<AppProvider>();
    // Persistimos antes para que el PDF y la base queden alineados.
    await _persistir(silencioso: true);
    try {
      await RepartoService.generarYCompartir(
        lista: _construirLista(),
        clientes: app.clientes,
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
          IconButton(
            tooltip: 'PDF para el repartidor',
            onPressed: _guardando ? null : _generarPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          _barraSemana(),
          _selectorDia(),
          const Divider(height: 1),
          if (_precargado && !_cargando) _bannerPrecargado(),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                    children: [
                      for (final tipo in tiposReparto) ...[
                        _tabla(app, tipo),
                        const SizedBox(height: 16),
                      ],
                      // NOTAS
                      TextField(
                        controller: _notasCtrl,
                        minLines: 2,
                        maxLines: 4,
                        onChanged: (_) => _marcarModificado(),
                        decoration: const InputDecoration(
                          labelText: 'Notas sueltas',
                          hintText: 'Ej: buscar morcillas de La Florida',
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
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
  Widget _tabla(AppProvider app, String tipo) {
    final filas = [..._filas[tipo]!]..sort((a, b) {
        final na = app.clientePorId(a.clienteId)?.nombreRazonSocial ?? '';
        final nb = app.clientePorId(b.clienteId)?.nombreRazonSocial ?? '';
        return compararNombres(na, nb);
      });
    final esCerdo = tipo == tipoRepartoCerdo;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
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
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11)),
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
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              children: [
                _filaHeader(),
                _filaTotal(tipo),
                const SizedBox(height: 4),
                if (filas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Todavía no hay clientes en esta tabla',
                      style: TextStyle(
                          fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  )
                else
                  for (final fila in filas) _filaCliente(app, tipo, fila),
                const SizedBox(height: 4),
                _filaSobrante(_sobrante(tipo)),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _agregarCliente(tipo),
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: Text(
                        'Agregar cliente a ${labelTipoReparto(tipo)}'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Expanded(
            child: Text('CLIENTE',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            width: 64,
            child: Text('MEDIAS',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _filaTotal(String tipo) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('TOTAL MEDIAS',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          _campoNumero(_totalCtrl[tipo]!),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _filaCliente(AppProvider app, String tipo, _Fila fila) {
    final cliente = app.clientePorId(fila.clienteId);
    final nombre = cliente?.nombreRazonSocial ?? '(cliente eliminado)';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        // El número va centrado contra el bloque del cliente (nombre +
        // sucursal): con alineación al tope quedaba más alto que el nombre.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(nombre, style: const TextStyle(fontSize: 14)),
                TextField(
                  controller: fila.sucursalCtrl,
                  maxLength: 40,
                  onChanged: (_) {
                    _marcarModificado();
                    setState(() {});
                  },
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
          ),
          const SizedBox(width: 8),
          _campoNumero(fila.mediasCtrl),
          SizedBox(
            width: 40,
            child: IconButton(
              tooltip: 'Quitar',
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close,
                  size: 18, color: AppTheme.textHint),
              onPressed: () {
                setState(() {
                  fila.dispose();
                  _filas[tipo]!.remove(fila);
                  _precargado = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaSobrante(int valor) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('SOBRANTE DEPÓSITO',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '$valor',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: valor < 0 ? AppTheme.danger : AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _campoNumero(TextEditingController ctrl) {
    return SizedBox(
      width: 64,
      child: TextField(
        controller: ctrl,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) {
          _marcarModificado();
          setState(() {});
        },
        decoration: const InputDecoration(
          isDense: true,
          contentPadding:
              EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          hintText: '0',
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

  _Fila({
    required this.clienteId,
    int medias = 0,
    String sucursal = '',
  })  : mediasCtrl =
            TextEditingController(text: medias == 0 ? '' : '$medias'),
        sucursalCtrl = TextEditingController(text: sucursal);

  int get cantidad => int.tryParse(mediasCtrl.text.trim()) ?? 0;

  void dispose() {
    mediasCtrl.dispose();
    sucursalCtrl.dispose();
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
