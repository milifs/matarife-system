// ============================================================
// ASISTENTE DE REPARTO (chatbox del robot)
// ============================================================
// Chat flotante para que Joaco arme el reparto por voz/texto.
// Escribe/dicta una frase ("para Perico 3 medias de carne el jueves y
// 5 de cerdo el sábado"), el asistente la interpreta con Claude (Edge
// Function parse-reparto), resuelve los nombres contra la lista de
// clientes y aplica los cambios DIRECTO en la base (reparto_listas /
// reparto_items).
//
// El DÍA lo dice el comando, no hay selector: una misma frase puede
// tocar dos días distintos, y cada pedido va a la lista de su día. Si
// un pedido no dice el día, el asistente lo pregunta en la propuesta
// en vez de adivinarlo.
//
// Es autónomo: no depende de la pantalla de reparto abierta. Por eso
// persiste con DatabaseService y NO toca el estado de RepartoScreen.
// Trabaja siempre sobre la semana actual (lunes de esta semana).
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/reparto_ia_service.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';

/// Abre el asistente de reparto como hoja modal (chatbox).
Future<void> mostrarAsistenteReparto(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AsistenteRepartoSheet(),
  );
}

// ─────────────────────────────────────────────
// Matcheo nombre → cliente
// ─────────────────────────────────────────────
List<Cliente> _matchClientes(String? nombre, List<Cliente> clientes) {
  if (nombre == null || nombre.trim().isEmpty) return [];
  final norm = normalizarBusqueda(nombre);
  final exactos = clientes
      .where((c) => normalizarBusqueda(c.nombreRazonSocial) == norm)
      .toList();
  if (exactos.isNotEmpty) return exactos;
  return clientes
      .where((c) => normalizarBusqueda(c.nombreRazonSocial).contains(norm))
      .toList();
}

// ─────────────────────────────────────────────
// Mensajes del chat
// ─────────────────────────────────────────────
enum _Rol { usuario, bot }

class _Mensaje {
  final _Rol rol;
  final String texto;

  /// Si el mensaje del bot trae una propuesta editable para revisar/aplicar.
  final _Propuesta? propuesta;

  _Mensaje.usuario(this.texto)
      : rol = _Rol.usuario,
        propuesta = null;
  _Mensaje.bot(this.texto, {this.propuesta}) : rol = _Rol.bot;
}

/// Propuesta interpretada (una tanda de items) esperando confirmación.
/// Los items pueden ser de días distintos: cada uno lleva el suyo.
class _Propuesta {
  final List<_Resolucion> resoluciones;
  bool aplicada = false;

  _Propuesta({required this.resoluciones});

  bool get hayAplicables => !aplicada && resoluciones.any((r) => r.aplicable);

  /// Los días que toca esta propuesta, en el orden de la semana.
  List<String> get dias => diasReparto
      .where((d) => resoluciones.any((r) => r.aplicable && r.dia == d))
      .toList();
}

class _Resolucion {
  final RepartoParseItem item;
  String? clienteId;

  /// Día destino de ESTE pedido. Arranca con el que dijo el comando y el
  /// usuario lo puede elegir si no lo dijo.
  String? dia;

  bool incluir = true;

  _Resolucion({required this.item, required this.clienteId})
      : dia = item.dia;

  /// Una carga sin medias no dice a qué tabla va (carne o cerdo), así que
  /// no se puede aplicar: hay que decir cuántas.
  bool get tieneCantidad =>
      item.esBorrar || item.carne > 0 || item.cerdo > 0;

  bool get aplicable =>
      incluir && clienteId != null && dia != null && tieneCantidad;
}

// ─────────────────────────────────────────────
// Hoja del chat
// ─────────────────────────────────────────────
class _AsistenteRepartoSheet extends StatefulWidget {
  const _AsistenteRepartoSheet();

  @override
  State<_AsistenteRepartoSheet> createState() => _AsistenteRepartoSheetState();
}

class _AsistenteRepartoSheetState extends State<_AsistenteRepartoSheet> {
  final _db = DatabaseService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final List<_Mensaje> _mensajes = [];
  bool _procesando = false;

  late final DateTime _semana; // lunes de esta semana

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    final lunes = hoy.subtract(Duration(days: hoy.weekday - 1));
    _semana = DateTime(lunes.year, lunes.month, lunes.day);
    _mensajes.add(_Mensaje.bot(
      'Hola Joaco. Decime qué cargar en el reparto y para qué día. '
      'Por ejemplo: "agregar para Perico 3 medias de carne para el jueves '
      'y 5 medias de cerdo para el sábado". '
      'Si no decís el día, te lo pregunto antes de guardar.',
    ));
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollAbajo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _enviar() async {
    final texto = _inputCtrl.text.trim();
    if (texto.isEmpty || _procesando) return;

    final app = context.read<AppProvider>();
    FocusScope.of(context).unfocus();

    setState(() {
      _mensajes.add(_Mensaje.usuario(texto));
      _procesando = true;
    });
    _inputCtrl.clear();
    _scrollAbajo();

    RepartoParseResult result;
    try {
      result = await RepartoIaService.interpretar(
        texto: texto,
        clientes: app.clientes.map((c) => c.nombreRazonSocial).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _procesando = false;
        _mensajes.add(_Mensaje.bot(
          'Uf, no pude interpretarlo (${'$e'.replaceFirst('Exception: ', '')}). '
          'Probá de nuevo, más cortito.',
        ));
      });
      _scrollAbajo();
      return;
    }

    if (!mounted) return;

    if (result.items.isEmpty) {
      setState(() {
        _procesando = false;
        _mensajes.add(_Mensaje.bot(
            'No entendí ningún pedido concreto. Probá decirlo de otra forma.'));
      });
      _scrollAbajo();
      return;
    }

    final resoluciones = result.items.map((it) {
      final matches = _matchClientes(it.cliente, app.clientes);
      return _Resolucion(
        item: it,
        clienteId: matches.length == 1 ? matches.first.id : null,
      );
    }).toList();

    final faltaDia = resoluciones.any((r) => r.dia == null);
    setState(() {
      _procesando = false;
      _mensajes.add(_Mensaje.bot(
        faltaDia
            ? 'Entendí esto, pero falta el día en alguno. Elegilo y confirmá:'
            : 'Entendí esto. Revisá y confirmá:',
        propuesta: _Propuesta(resoluciones: resoluciones),
      ));
    });
    _scrollAbajo();
  }

  /// Muestra la lista de reparto actual de un día (para revisar sobre qué
  /// se está trabajando antes o después de dictar cambios).
  Future<void> _verLista(String dia) async {
    final app = context.read<AppProvider>();
    setState(() => _procesando = true);
    ({RepartoLista lista, bool precargado}) res;
    try {
      res = await _db.getRepartoListaOPlantilla(_semana, dia);
    } catch (_) {
      if (!mounted) return;
      setState(() => _procesando = false);
      return;
    }
    if (!mounted) return;
    setState(() => _procesando = false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _VistaLista(
        dia: dia,
        lista: res.lista,
        precargado: res.precargado,
        nombre: (id) =>
            app.clientePorId(id)?.nombreRazonSocial ?? '(cliente eliminado)',
      ),
    );
  }

  Future<void> _elegirCliente(_Resolucion r) async {
    final app = context.read<AppProvider>();
    final elegido = await showModalBottomSheet<Cliente>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SelectorCliente(clientes: app.clientes),
    );
    if (elegido != null && mounted) {
      setState(() => r.clienteId = elegido.id);
    }
  }

  Future<void> _aplicar(_Propuesta prop) async {
    setState(() => _procesando = true);

    final aplicables = prop.resoluciones.where((r) => r.aplicable).toList();

    try {
      final resumenes = <String>[];
      // Un pedido por día: cada día es una lista aparte en la base.
      for (final dia in prop.dias) {
        // Cargar la lista del día en la semana actual. Si todavía no existe,
        // viene sembrada con la de la semana anterior, así el update /
        // insert / delete se hace sobre esa base (los clientes que repiten).
        final lista = (await _db.getRepartoListaOPlantilla(_semana, dia)).lista;
        final items = List<RepartoItem>.from(lista.items);

        var cargados = 0;
        var borrados = 0;
        for (final r in aplicables.where((r) => r.dia == dia)) {
          if (r.item.esBorrar) {
            // Sacar al cliente lo saca de las dos tablas de ese día.
            final antes = items.length;
            items.removeWhere((it) => it.clienteId == r.clienteId);
            if (items.length < antes) borrados++;
            continue;
          }
          // Una fila por mercadería: solo se toca la que el pedido menciona,
          // para no pisar en cero lo que ya tenía cargado en la otra tabla.
          final pedido = {
            tipoRepartoCarne: r.item.carne,
            tipoRepartoCerdo: r.item.cerdo,
          };
          pedido.forEach((tipo, medias) {
            if (medias <= 0) return;
            final idx = items.indexWhere(
                (it) => it.clienteId == r.clienteId && it.tipo == tipo);
            if (idx >= 0) {
              items[idx].medias = medias;
              if (r.item.sucursal.isNotEmpty) {
                items[idx].sucursal = r.item.sucursal;
              }
            } else {
              items.add(RepartoItem(
                clienteId: r.clienteId!,
                tipo: tipo,
                medias: medias,
                sucursal: r.item.sucursal,
                orden: items.length,
              ));
            }
          });
          cargados++;
        }

        lista.items = items;
        await _db.guardarReparto(lista);
        resumenes.add(
            '${labelDiaReparto(dia)}: ${_resumenAplicado(cargados, borrados)}');
      }

      if (!mounted) return;
      setState(() {
        prop.aplicada = true;
        _procesando = false;
        _mensajes.add(_Mensaje.bot(resumenes.isEmpty
            ? 'No hubo cambios para aplicar.'
            : resumenes.join('\n')));
      });
      _scrollAbajo();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _procesando = false;
        _mensajes.add(_Mensaje.bot(
            'No pude guardar (${'$e'.replaceFirst('Exception: ', '')}). Probá de nuevo.'));
      });
      _scrollAbajo();
    }
  }

  /// Fragmento en minúscula: se compone con el día ("Jueves: cargué 2…").
  String _resumenAplicado(int cargados, int borrados) {
    final partes = <String>[];
    if (cargados > 0) {
      partes.add('cargué $cargados ${cargados == 1 ? "cliente" : "clientes"}');
    }
    if (borrados > 0) {
      partes.add('saqué $borrados ${borrados == 1 ? "cliente" : "clientes"}');
    }
    if (partes.isEmpty) return 'no hubo cambios';
    return partes.join(' y ');
  }

  @override
  Widget build(BuildContext context) {
    final alto = MediaQuery.of(context).size.height * 0.85;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: alto,
        decoration: const BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _encabezado(),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                itemCount: _mensajes.length + (_procesando ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i >= _mensajes.length) return _burbujaEscribiendo();
                  return _burbuja(_mensajes[i]);
                },
              ),
            ),
            _barraInput(),
          ],
        ),
      ),
    );
  }

  Widget _encabezado() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
            child: const Icon(Icons.smart_toy, color: AppTheme.primary),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Asistente de reparto',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                Text('Decí el pedido y el día',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          // Ya no hay día elegido: el día lo dice el comando, así que
          // para mirar una lista hay que decir cuál.
          PopupMenuButton<String>(
            tooltip: 'Ver la lista de un día',
            enabled: !_procesando,
            icon: const Icon(Icons.receipt_long),
            onSelected: _verLista,
            itemBuilder: (_) => [
              for (final d in diasReparto)
                PopupMenuItem(
                    value: d, child: Text('Ver el ${labelDiaReparto(d)}')),
            ],
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _burbuja(_Mensaje m) {
    final esUsuario = m.rol == _Rol.usuario;
    return Align(
      alignment: esUsuario ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: esUsuario ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(esUsuario ? 16 : 4),
            bottomRight: Radius.circular(esUsuario ? 4 : 16),
          ),
          border: esUsuario
              ? null
              : Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m.texto,
              style: TextStyle(
                fontSize: 14,
                color: esUsuario ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            if (m.propuesta != null) _panelPropuesta(m.propuesta!),
          ],
        ),
      ),
    );
  }

  Widget _panelPropuesta(_Propuesta prop) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in prop.resoluciones) _itemPropuesta(prop, r),
          const SizedBox(height: 4),
          if (!prop.aplicada)
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        prop.hayAplicables ? () => _aplicar(prop) : null,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Confirmar'),
                  ),
                ),
              ],
            )
          else
            const Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: AppTheme.success),
                SizedBox(width: 6),
                Text('Aplicado',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.success,
                        fontWeight: FontWeight.w600)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _itemPropuesta(_Propuesta prop, _Resolucion r) {
    final app = context.read<AppProvider>();
    final cliente = r.clienteId == null ? null : app.clientePorId(r.clienteId!);
    final esBorrar = r.item.esBorrar;
    final bloqueado = prop.aplicada;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!bloqueado)
            SizedBox(
              width: 28,
              child: Checkbox(
                value: r.incluir,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => setState(() => r.incluir = v ?? false),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: esBorrar
                            ? AppTheme.danger.withValues(alpha: 0.15)
                            : AppTheme.success.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        esBorrar ? 'BORRAR' : 'CARGAR',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color:
                              esBorrar ? AppTheme.danger : AppTheme.success,
                        ),
                      ),
                    ),
                    if (!esBorrar && r.tieneCantidad) ...[
                      const SizedBox(width: 6),
                      Text(_cantidades(r.item),
                          style: const TextStyle(fontSize: 12)),
                    ],
                    const SizedBox(width: 6),
                    _chipDia(prop, r),
                  ],
                ),
                if (!r.tieneCantidad)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text('Falta decir cuántas medias',
                        style:
                            TextStyle(fontSize: 11, color: AppTheme.danger)),
                  ),
                const SizedBox(height: 4),
                if (cliente != null)
                  InkWell(
                    onTap: bloqueado ? null : () => _elegirCliente(r),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(cliente.nombreRazonSocial,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (!bloqueado) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.edit,
                              size: 13, color: AppTheme.textHint),
                        ],
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      const Icon(Icons.help_outline,
                          size: 15, color: AppTheme.danger),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          r.item.cliente == null
                              ? 'No reconocí el cliente'
                              : 'No encontré "${r.item.cliente}"',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.danger),
                        ),
                      ),
                      if (!bloqueado)
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 0),
                            tapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _elegirCliente(r),
                          child: const Text('Elegir'),
                        ),
                    ],
                  ),
                if (cliente != null && r.item.sucursal.isNotEmpty)
                  Text('Sucursal: ${r.item.sucursal}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary)),
                if (cliente != null &&
                    r.item.confianza == 'dudosa' &&
                    !bloqueado)
                  const Text('Revisá que sea el cliente correcto',
                      style:
                          TextStyle(fontSize: 10, color: AppTheme.warning)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Solo las mercaderías que el pedido nombró: si dijo únicamente carne,
  /// mostrar "0 cerdo" al lado haría dudar de que se vaya a pisar.
  String _cantidades(RepartoParseItem item) {
    final partes = <String>[];
    if (item.carne > 0) partes.add('${item.carne} carne');
    if (item.cerdo > 0) partes.add('${item.cerdo} cerdo');
    return partes.join(' · ');
  }

  /// Día de este pedido. Si el comando no lo dijo, queda en rojo pidiéndolo:
  /// sin día no se puede guardar, porque cada día es una lista distinta.
  Widget _chipDia(_Propuesta prop, _Resolucion r) {
    final falta = r.dia == null;
    final bloqueado = prop.aplicada;
    final color = falta ? AppTheme.danger : AppTheme.info;
    return InkWell(
      onTap: bloqueado ? null : () => _elegirDia(r),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event, size: 12, color: color),
            const SizedBox(width: 3),
            Text(
              falta ? '¿Qué día?' : labelDiaReparto(r.dia!),
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color),
            ),
            if (!bloqueado)
              Icon(Icons.arrow_drop_down, size: 14, color: color),
          ],
        ),
      ),
    );
  }

  Future<void> _elegirDia(_Resolucion r) async {
    final elegido = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('¿Para qué día es?',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              ),
            ),
            for (final d in diasReparto)
              ListTile(
                leading: const Icon(Icons.event),
                title: Text(labelDiaReparto(d)),
                selected: r.dia == d,
                onTap: () => Navigator.pop(ctx, d),
              ),
          ],
        ),
      ),
    );
    if (elegido != null && mounted) setState(() => r.dia = elegido);
  }

  Widget _burbujaEscribiendo() {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: 10, left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Pensando…',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _barraInput() {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _enviar(),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.background,
                  hintText: 'Escribí o dictá el pedido…',
                  hintStyle: const TextStyle(fontSize: 14),
                  prefixIcon: const Icon(Icons.mic_none, size: 22),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _procesando
                ? const SizedBox(
                    width: 44,
                    height: 44,
                    child: Padding(
                      padding: EdgeInsets.all(11),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton.filled(
                    tooltip: 'Enviar',
                    onPressed: _enviar,
                    icon: const Icon(Icons.send),
                  ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Vista de la lista de reparto del día (solo lectura)
// ─────────────────────────────────────────────
class _VistaLista extends StatelessWidget {
  final String dia;
  final RepartoLista lista;
  final bool precargado;
  final String Function(String clienteId) nombre;

  const _VistaLista({
    required this.dia,
    required this.lista,
    required this.precargado,
    required this.nombre,
  });

  @override
  Widget build(BuildContext context) {
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
          Row(
            children: [
              Expanded(
                child: Text('Reparto del ${labelDiaReparto(dia)}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w600)),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (precargado)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Precargado de la semana pasada (todavía sin guardar).',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          // Una tabla por mercadería, igual que la pantalla de reparto.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final tipo in tiposReparto) _tabla(tipo),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabla(String tipo) {
    final items = [...lista.itemsDe(tipo)]
      ..sort((a, b) =>
          compararNombres(nombre(a.clienteId), nombre(b.clienteId)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Text(
          tipo == tipoRepartoCerdo ? 'CERDO' : 'CARNE (NOVILLO)',
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.primary),
        ),
        const SizedBox(height: 2),
        _fila('CLIENTE', 'MEDIAS', header: true),
        _fila('TOTAL MEDIAS', '${lista.totalDe(tipo)}', bold: true),
        const Divider(height: 12),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Todavía no hay clientes acá',
                style: TextStyle(color: AppTheme.textSecondary)),
          )
        else
          for (final it in items)
            _fila(
              nombre(it.clienteId) +
                  (it.sucursal.isNotEmpty ? ' (${it.sucursal})' : ''),
              it.medias == 0 ? '' : '${it.medias}',
            ),
        const Divider(height: 12),
        _fila('SOBRANTE DEPÓSITO', '${lista.sobranteDe(tipo)}', bold: true),
      ],
    );
  }

  Widget _fila(String cliente, String medias,
      {bool header = false, bool bold = false}) {
    final estilo = TextStyle(
      fontSize: header ? 12 : 14,
      fontWeight: (header || bold) ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(cliente, style: estilo)),
          SizedBox(
              width: 56,
              child: Text(medias, textAlign: TextAlign.center, style: estilo)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Selector de cliente (búsqueda + lista A→Z)
// (copia local para que el asistente sea autónomo)
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
          const Text('Elegí el cliente',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
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
                          style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: lista.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
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
