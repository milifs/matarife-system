// ============================================================
// PANTALLA DE REPARTO - Logística semanal de medias
// ============================================================
// Grilla estilo planilla: clientes × CARNE (novillo) / CERDO.
// Dos listas por semana (Jueves / Viernes), navegable por semana.
// TOTAL MEDIAS se carga a mano; el SOBRANTE se calcula solo.
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

  final _totalCarneCtrl = TextEditingController();
  final _totalCerdoCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();
  List<_Fila> _filas = [];

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
    _totalCarneCtrl.dispose();
    _totalCerdoCtrl.dispose();
    _notasCtrl.dispose();
    for (final f in _filas) {
      f.dispose();
    }
    super.dispose();
  }

  bool get _hayContenido =>
      _filas.isNotEmpty ||
      _totalCarneCtrl.text.trim().isNotEmpty ||
      _totalCerdoCtrl.text.trim().isNotEmpty ||
      _notasCtrl.text.trim().isNotEmpty;

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    // Si la semana todavía no tiene lista, viene sembrada con la de la semana
    // anterior (misma lógica que usa el asistente de reparto).
    final res = await _db.getRepartoListaOPlantilla(_semana, _dia);
    final lista = res.lista;

    for (final f in _filas) {
      f.dispose();
    }
    _filas = [];
    _precargado = res.precargado;

    _totalCarneCtrl.text =
        lista.totalMediasCarne == 0 ? '' : '${lista.totalMediasCarne}';
    _totalCerdoCtrl.text =
        lista.totalMediasCerdo == 0 ? '' : '${lista.totalMediasCerdo}';
    _notasCtrl.text = lista.notas;
    for (final it in lista.items) {
      _filas.add(_Fila(
        clienteId: it.clienteId,
        carne: it.mediasCarne,
        cerdo: it.mediasCerdo,
        sucursal: it.sucursal,
      ));
    }

    if (mounted) setState(() => _cargando = false);
  }

  RepartoLista _construirLista() {
    final items = <RepartoItem>[];
    for (var i = 0; i < _filas.length; i++) {
      final f = _filas[i];
      items.add(RepartoItem(
        clienteId: f.clienteId,
        mediasCarne: int.tryParse(f.carneCtrl.text.trim()) ?? 0,
        mediasCerdo: int.tryParse(f.cerdoCtrl.text.trim()) ?? 0,
        sucursal: f.sucursalCtrl.text.trim(),
        orden: i,
      ));
    }
    return RepartoLista(
      semanaInicio: _semana,
      dia: _dia,
      totalMediasCarne: int.tryParse(_totalCarneCtrl.text.trim()) ?? 0,
      totalMediasCerdo: int.tryParse(_totalCerdoCtrl.text.trim()) ?? 0,
      notas: _notasCtrl.text.trim(),
      items: items,
    );
  }

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

  Future<void> _agregarCliente() async {
    final app = context.read<AppProvider>();
    // Se permite agregar el mismo cliente más de una vez (una fila por
    // sucursal), así que no se excluyen los ya agregados.
    final disponibles = app.clientes.toList()
      ..sort((a, b) =>
          a.nombreRazonSocial.toLowerCase().compareTo(
              b.nombreRazonSocial.toLowerCase()));

    final elegido = await showModalBottomSheet<Cliente>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _SelectorCliente(clientes: disponibles),
    );

    if (elegido == null) return;
    setState(() {
      _filas.add(_Fila(clienteId: elegido.id));
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

  int _sumaCarne() => _filas.fold(
      0, (s, f) => s + (int.tryParse(f.carneCtrl.text.trim()) ?? 0));
  int _sumaCerdo() => _filas.fold(
      0, (s, f) => s + (int.tryParse(f.cerdoCtrl.text.trim()) ?? 0));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final totalCarne = int.tryParse(_totalCarneCtrl.text.trim()) ?? 0;
    final totalCerdo = int.tryParse(_totalCerdoCtrl.text.trim()) ?? 0;
    final sobranteCarne = totalCarne - _sumaCarne();
    final sobranteCerdo = totalCerdo - _sumaCerdo();

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
                : _grilla(app, sobranteCarne, sobranteCerdo),
          ),
        ],
      ),
      floatingActionButton: _cargando
          ? null
          : FloatingActionButton.extended(
              onPressed: _agregarCliente,
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

  Widget _selectorDia() {
    return Container(
      color: AppTheme.card,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'jueves', label: Text('Jueves')),
          ButtonSegment(value: 'viernes', label: Text('Viernes')),
        ],
        selected: {_dia},
        onSelectionChanged: (s) => _cambiarDia(s.first),
      ),
    );
  }

  Widget _grilla(AppProvider app, int sobranteCarne, int sobranteCerdo) {
    final filasOrdenadas = [..._filas]..sort((a, b) {
      final na = app.clientePorId(a.clienteId)?.nombreRazonSocial ?? '';
      final nb = app.clientePorId(b.clienteId)?.nombreRazonSocial ?? '';
      return na.toLowerCase().compareTo(nb.toLowerCase());
    });
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      children: [
        // Encabezado de columnas
        _filaHeader(),
        // TOTAL MEDIAS (editable a mano)
        _filaTotal(),
        const SizedBox(height: 4),
        // Filas de clientes
        if (_filas.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Column(
              children: [
                Icon(Icons.local_shipping_outlined,
                    size: 40, color: AppTheme.textHint),
                SizedBox(height: 8),
                Text('Todavía no hay clientes en esta lista',
                    style: TextStyle(color: AppTheme.textSecondary)),
                SizedBox(height: 4),
                Text('Usá "Agregar cliente" para empezar',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textHint)),
              ],
            ),
          )
        else
          for (final fila in filasOrdenadas) _filaCliente(app, fila),
        const SizedBox(height: 4),
        // SOBRANTE DEPÓSITO (calculado)
        _filaSobrante(sobranteCarne, sobranteCerdo),
        const SizedBox(height: 20),
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
    );
  }

  Widget _filaHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        children: [
          Expanded(
            child: Text('CLIENTES',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            width: 64,
            child: Text('CARNE',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 8),
          SizedBox(
            width: 64,
            child: Text('CERDO',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _filaTotal() {
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
          _campoNumero(_totalCarneCtrl),
          const SizedBox(width: 8),
          _campoNumero(_totalCerdoCtrl),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _filaCliente(AppProvider app, _Fila fila) {
    final cliente = app.clientePorId(fila.clienteId);
    final nombre = cliente?.nombreRazonSocial ?? '(cliente eliminado)';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
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
                        EdgeInsets.symmetric(vertical: 4, horizontal: 0),
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
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _campoNumero(fila.carneCtrl),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _campoNumero(fila.cerdoCtrl),
          ),
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
                  _filas.remove(fila);
                  _precargado = false;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaSobrante(int carne, int cerdo) {
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
          _celdaSobrante(carne),
          const SizedBox(width: 8),
          _celdaSobrante(cerdo),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _celdaSobrante(int valor) {
    return SizedBox(
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
// Fila editable en memoria
// ─────────────────────────────────────────────
class _Fila {
  final String clienteId;
  final TextEditingController carneCtrl;
  final TextEditingController cerdoCtrl;
  final TextEditingController sucursalCtrl;

  _Fila({
    required this.clienteId,
    int carne = 0,
    int cerdo = 0,
    String sucursal = '',
  })  : carneCtrl =
            TextEditingController(text: carne == 0 ? '' : '$carne'),
        cerdoCtrl =
            TextEditingController(text: cerdo == 0 ? '' : '$cerdo'),
        sucursalCtrl = TextEditingController(text: sucursal);

  void dispose() {
    carneCtrl.dispose();
    cerdoCtrl.dispose();
    sucursalCtrl.dispose();
  }
}

// ─────────────────────────────────────────────
// Selector de cliente (búsqueda + lista A→Z)
// ─────────────────────────────────────────────
class _SelectorCliente extends StatefulWidget {
  final List<Cliente> clientes;
  const _SelectorCliente({required this.clientes});

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
          const Text('Agregar cliente al reparto',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
