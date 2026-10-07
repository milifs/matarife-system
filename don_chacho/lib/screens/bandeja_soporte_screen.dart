// ============================================================
// BANDEJA DE SOPORTE (solo admin)
// ============================================================
// Triage de los reclamos: 3 tabs por estado. Desde cada ticket se pasa a
// "en revisión" o se resuelve dejando una respuesta, que es lo que ve el
// usuario que lo reportó.
// ============================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/database_service.dart';
import '../services/soporte_service.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';

class BandejaSoporteScreen extends StatefulWidget {
  const BandejaSoporteScreen({super.key});

  @override
  State<BandejaSoporteScreen> createState() => _BandejaSoporteScreenState();
}

class _BandejaSoporteScreenState extends State<BandejaSoporteScreen> {
  final _db = DatabaseService();

  bool _cargando = true;
  String? _error;
  List<TicketSoporte> _tickets = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final tickets = await _db.getTicketsSoporte();
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final abiertos = _tickets.where((t) => t.esAbierto).toList();
    final enRevision = _tickets.where((t) => t.esEnRevision).toList();
    final resueltos = _tickets.where((t) => t.esResuelto).toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Soporte'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
              onPressed: _cargar,
            ),
          ],
          bottom: TabBar(
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textSecondary,
            indicatorColor: AppTheme.primary,
            tabs: [
              Tab(text: 'Abiertos (${abiertos.length})'),
              Tab(text: 'En revisión (${enRevision.length})'),
              Tab(text: 'Resueltos (${resueltos.length})'),
            ],
          ),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : TabBarView(
                    children: [
                      _buildLista(abiertos, 'No hay reclamos abiertos'),
                      _buildLista(enRevision, 'Nada en revisión'),
                      _buildLista(resueltos, 'Todavía no resolviste ninguno'),
                    ],
                  ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 40, color: AppTheme.textHint),
            const SizedBox(height: 12),
            const Text(
              'No se pudieron cargar los reclamos.\n¿Corriste la migración '
              'supabase_migration_soporte.sql?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _cargar,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLista(List<TicketSoporte> tickets, String vacio) {
    if (tickets.isEmpty) {
      return Center(
        child: Text(vacio,
            style: const TextStyle(fontSize: 13, color: AppTheme.textHint)),
      );
    }
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: tickets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _TicketCard(
          ticket: tickets[i],
          onAbrir: () => _abrirTicket(tickets[i]),
        ),
      ),
    );
  }

  Future<void> _abrirTicket(TicketSoporte ticket) async {
    final cambio = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _TicketDetalle(ticket: ticket)),
    );
    if (cambio == true) _cargar();
  }
}

// ─────────────────────────────────────────────
// Card de la lista
// ─────────────────────────────────────────────
class _TicketCard extends StatelessWidget {
  final TicketSoporte ticket;
  final VoidCallback onAbrir;

  const _TicketCard({required this.ticket, required this.onAbrir});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onAbrir,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(ticket.numeroFormateado,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  if (ticket.bloqueante)
                    const StatusPill(
                        text: 'Urgente', type: StatusType.danger),
                  const Spacer(),
                  if (ticket.tieneAdjunto)
                    const Icon(Icons.image_outlined,
                        size: 16, color: AppTheme.textHint),
                  const SizedBox(width: 6),
                  Text(formatFechaCorta(ticket.creadoEn),
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textHint)),
                ],
              ),
              const SizedBox(height: 6),
              Text(ticket.modulo,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text(
                ticket.descripcion,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                '${ticket.reportadoPor ?? '—'} · ${ticket.plataforma ?? '—'}',
                style: const TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Detalle + triage
// ─────────────────────────────────────────────
class _TicketDetalle extends StatefulWidget {
  final TicketSoporte ticket;

  const _TicketDetalle({required this.ticket});

  @override
  State<_TicketDetalle> createState() => _TicketDetalleState();
}

class _TicketDetalleState extends State<_TicketDetalle> {
  final _db = DatabaseService();
  final _soporte = SoporteService();
  late final TextEditingController _respuestaCtrl;

  bool _guardando = false;
  String? _urlAdjunto;

  @override
  void initState() {
    super.initState();
    _respuestaCtrl = TextEditingController(text: widget.ticket.respuesta);
    if (widget.ticket.tieneAdjunto) _cargarAdjunto();
  }

  @override
  void dispose() {
    _respuestaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarAdjunto() async {
    try {
      final url = await _soporte.urlAdjunto(widget.ticket.adjuntoPath!);
      if (mounted) setState(() => _urlAdjunto = url);
    } catch (_) {
      // Sin link no se puede mostrar la foto; el resto del ticket sirve igual.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;

    return Scaffold(
      appBar: AppBar(title: Text(t.numeroFormateado)),
      body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusPill(
                          text: t.estadoLabel,
                          type: switch (t.estado) {
                            'resuelto' => StatusType.success,
                            'en_revision' => StatusType.info,
                            _ => StatusType.warning,
                          },
                        ),
                        const SizedBox(width: 8),
                        if (t.bloqueante)
                          const StatusPill(
                              text: 'Urgente', type: StatusType.danger),
                      ],
                    ),
                    const Divider(height: 24),
                    _fila('Módulo', t.modulo),
                    _fila('Reportado por', t.reportadoPor ?? '—'),
                    if ((t.rol ?? '').isNotEmpty) _fila('Rol', t.rol!),
                    _fila('Fecha', formatFechaHora(t.creadoEn)),
                    _fila('App', '${t.appVersion ?? '—'} · '
                        '${t.plataforma ?? '—'}'),
                    if (t.resueltoEn != null)
                      _fila('Resuelto', formatFechaHora(t.resueltoEn!)),
                    const Divider(height: 24),
                    const Text('Problema',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Text(t.descripcion,
                        style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ),

            // ── Adjunto ──
            if (t.tieneAdjunto) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      if (_urlAdjunto == null)
                        const SizedBox(
                          height: 60,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _urlAdjunto!,
                            fit: BoxFit.contain,
                            // Las fotos de iPhone pueden venir en HEIC, que el
                            // navegador no renderiza: ahí queda el botón de abrir.
                            errorBuilder: (_, __, ___) => Container(
                              height: 60,
                              alignment: Alignment.center,
                              child: const Text(
                                'No se puede previsualizar este formato',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _urlAdjunto == null
                            ? null
                            : () => launchUrl(Uri.parse(_urlAdjunto!),
                                mode: LaunchMode.externalApplication),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Abrir la foto'),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // ── Respuesta ──
            TextField(
              controller: _respuestaCtrl,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Respuesta para el cliente',
                hintText: 'Ej: ya está corregido, actualizá la app.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),

            if (!t.esEnRevision && !t.esResuelto)
              OutlinedButton.icon(
                onPressed: _guardando
                    ? null
                    : () => _cambiarEstado('en_revision'),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Marcar en revisión'),
              ),
            if (!t.esResuelto) ...[
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed:
                    _guardando ? null : () => _cambiarEstado('resuelto'),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Marcar resuelto'),
              ),
            ] else ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed:
                    _guardando ? null : () => _cambiarEstado('abierto'),
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Reabrir'),
              ),
            ],
            const SizedBox(height: 40),
          ],
      ),
    );
  }

  Widget _fila(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Future<void> _cambiarEstado(String estado) async {
    setState(() => _guardando = true);
    final t = widget.ticket;
    final app = context.read<AppProvider>();

    t.estado = estado;
    t.respuesta = _respuestaCtrl.text.trim();
    if (estado == 'resuelto') {
      t.resueltoEn = DateTime.now();
      t.resueltoPor = app.usuarioActual?.nombreCompleto;
    } else {
      t.resueltoEn = null;
      t.resueltoPor = null;
    }

    try {
      await _db.updateTicketSoporte(t);
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar: $e'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }
}
