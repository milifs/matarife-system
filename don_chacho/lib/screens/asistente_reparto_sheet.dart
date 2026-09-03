// ============================================================
// ASISTENTE DE REPARTO (chatbox del robot)
// ============================================================
// Chat flotante para que Joaco arme el reparto por voz/texto.
// Escribe/dicta una frase ("3 de cerdo y 2 de carne para Perico"),
// el asistente la interpreta con Claude (Edge Function parse-reparto),
// resuelve los nombres contra la lista de clientes y aplica los
// cambios DIRECTO en la base (reparto_listas / reparto_items).
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
class _Propuesta {
  final String dia; // 'jueves' | 'viernes' — día destino ya resuelto
  final List<_Resolucion> resoluciones;
  bool aplicada = false;

  _Propuesta({required this.dia, required this.resoluciones});

  bool get hayAplicables =>
      !aplicada && resoluciones.any((r) => r.incluir && r.clienteId != null);
}

class _Resolucion {
  final RepartoParseItem item;
  String? clienteId;
  bool incluir = true;
  _Resolucion({required this.item, required this.clienteId});
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
  String _dia = 'jueves'; // día destino por defecto
  bool _procesando = false;

  late final DateTime _semana; // lunes de esta semana

  @override
  void initState() {
    super.initState();
    final hoy = DateTime.now();
    final lunes = hoy.subtract(Duration(days: hoy.weekday - 1));
    _semana = DateTime(lunes.year, lunes.month, lunes.day);
    _mensajes.add(_Mensaje.bot(
      'Hola Joaco. Decime qué cargar en el reparto. Por ejemplo: '
      '"3 medias de cerdo y 2 de carne para Perico". '
      'Podés nombrar el día (jueves o viernes) o dejar el que está elegido acá arriba.',
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
        diaActual: _dia,
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

    // Día destino: el que detectó la IA, o el elegido en la barra.
    final diaDestino = result.dia ?? _dia;
    final resoluciones = result.items.map((it) {
      final matches = _matchClientes(it.cliente, app.clientes);
      return _Resolucion(
        item: it,
        clienteId: matches.length == 1 ? matches.first.id : null,
      );
    }).toList();

    setState(() {
      _dia = diaDestino;
      _procesando = false;
      _mensajes.add(_Mensaje.bot(
        'Entendí esto para el ${_cap(diaDestino)}. Revisá y confirmá:',
        propuesta:
            _Propuesta(dia: diaDestino, resoluciones: resoluciones),
      ));
    });
    _scrollAbajo();
  }

  Future<void> _elegirCliente(_Resolucion r) async {
    final app = context.read<AppProvider>();
    final ordenados = app.clientes.toList()
      ..sort((a, b) => a.nombreRazonSocial
          .toLowerCase()
          .compareTo(b.nombreRazonSocial.toLowerCase()));
    final elegido = await showModalBottomSheet<Cliente>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SelectorCliente(clientes: ordenados),
    );
    if (elegido != null && mounted) {
      setState(() => r.clienteId = elegido.id);
    }
  }

  Future<void> _aplicar(_Propuesta prop) async {
    setState(() => _procesando = true);

    final aplicables = prop.resoluciones
        .where((r) => r.incluir && r.clienteId != null)
        .toList();

    try {
      // Cargar (o crear) la lista del día destino en la semana actual.
      final existente = await _db.getRepartoLista(_semana, prop.dia);
      final lista = existente ??
          RepartoLista(semanaInicio: _semana, dia: prop.dia, items: []);
      final items = List<RepartoItem>.from(lista.items);

      var cargados = 0;
      var borrados = 0;
      for (final r in aplicables) {
        if (r.item.esBorrar) {
          final antes = items.length;
          items.removeWhere((it) => it.clienteId == r.clienteId);
          if (items.length < antes) borrados++;
        } else {
          final idx = items.indexWhere((it) => it.clienteId == r.clienteId);
          if (idx >= 0) {
            final it = items[idx];
            if (r.item.carne > 0) it.mediasCarne = r.item.carne;
            if (r.item.cerdo > 0) it.mediasCerdo = r.item.cerdo;
            if (r.item.sucursal.isNotEmpty) it.sucursal = r.item.sucursal;
          } else {
            items.add(RepartoItem(
              clienteId: r.clienteId!,
              mediasCarne: r.item.carne,
              mediasCerdo: r.item.cerdo,
              sucursal: r.item.sucursal,
              orden: items.length,
            ));
          }
          cargados++;
        }
      }

      lista.items = items;
      await _db.guardarReparto(lista);

      if (!mounted) return;
      setState(() {
        prop.aplicada = true;
        _procesando = false;
        _mensajes.add(_Mensaje.bot(
            '${_resumenAplicado(cargados, borrados)} en el ${_cap(prop.dia)}.'));
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

  String _resumenAplicado(int cargados, int borrados) {
    final partes = <String>[];
    if (cargados > 0) {
      partes.add('Cargué $cargados ${cargados == 1 ? "cliente" : "clientes"}');
    }
    if (borrados > 0) {
      partes.add('saqué $borrados ${borrados == 1 ? "cliente" : "clientes"}');
    }
    if (partes.isEmpty) return 'No hubo cambios';
    final txt = partes.join(' y ');
    return '${txt[0].toUpperCase()}${txt.substring(1)}';
  }

  String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

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
                Text('Cargá el reparto hablando',
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          // Selector de día destino
          SegmentedButton<String>(
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            segments: const [
              ButtonSegment(value: 'jueves', label: Text('Jue')),
              ButtonSegment(value: 'viernes', label: Text('Vie')),
            ],
            selected: {_dia},
            onSelectionChanged: (s) => setState(() => _dia = s.first),
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
                    if (!esBorrar) ...[
                      const SizedBox(width: 6),
                      Text('${r.item.carne} carne · ${r.item.cerdo} cerdo',
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ],
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
