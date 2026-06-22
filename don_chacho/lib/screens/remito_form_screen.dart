// ============================================================
// FORMULARIO REMITO - Con OCR de foto + carga manual
// ============================================================
// Flujo OCR: foto → Claude API extrae datos → verificás → guardás
// Flujo manual: completás los campos a mano
// Regla tipo carne: media > 60kg = Novillo, <= 60kg = Cerdo
// ============================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';
import '../services/ocr_service.dart';

class RemitoFormScreen extends StatefulWidget {
  final Remito? remitoInicial;
  const RemitoFormScreen({super.key, this.remitoInicial});

  @override
  State<RemitoFormScreen> createState() => _RemitoFormScreenState();
}

class _RemitoFormScreenState extends State<RemitoFormScreen> {
  String? _clienteId;
  DateTime _fecha = DateTime.now();
  List<_ItemForm> _items = [_ItemForm()];
  bool _guardando = false;
  bool _leyendoOcr = false;
  String? _ocrError;
  Uint8List? _fotoBytes;
  bool _ocrCompletado = false;
  int _ocrRebuildKey = 0; // Se incrementa después del OCR para forzar rebuild
  String _busquedaCliente = '';

  bool get _esEdicion => widget.remitoInicial != null;

  @override
  void initState() {
    super.initState();
    if (widget.remitoInicial != null) {
      _clienteId = widget.remitoInicial!.clienteId;
      _fecha = widget.remitoInicial!.fecha;
      // Cargar items del remito existente
      final app = context.read<AppProvider>();
      final items = app.itemsDeRemito(widget.remitoInicial!.id);
      if (items.isNotEmpty) {
        _items = items
            .map((i) => _ItemForm()
              ..tipoCarne = i.tipoCarne
              ..cantidadMedias = i.cantidadMedias
              ..kg = i.kgTotal
              ..precioPorKg = i.precioPorKg)
            .toList();
      }
    }
  }

  double get _totalKg =>
      _items.fold(0, (sum, i) => sum + (i.kg ?? 0));

  double get _totalPesos => _items.fold(
      0, (sum, i) => sum + ((i.kg ?? 0) * (i.precioPorKg ?? 0)));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion ? 'Editar remito' : 'Nuevo remito'),
        actions: [
          if (_esEdicion && app.tienePermiso('eliminar_remito'))
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
              onPressed: _guardando ? null : _confirmarEliminar,
              tooltip: 'Eliminar',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Zona de foto + OCR (solo si tiene permiso) ──
          if (app.tienePermiso('usar_ocr')) ...[
            _buildFotoSection(),
            const SizedBox(height: 16),
          ],

          // ── Cliente: búsqueda + dropdown A→Z ──
          TextField(
            decoration: InputDecoration(
              labelText: 'Buscar cliente',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _busquedaCliente.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() {
                        _busquedaCliente = '';
                      }),
                    )
                  : null,
            ),
            onChanged: (v) => setState(() {
              _busquedaCliente = v;
            }),
          ),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            // Ordenar A→Z
            var clientesOrdenados = app.clientes.toList()
              ..sort((a, b) => a.nombreRazonSocial
                  .compareTo(b.nombreRazonSocial));
            // Filtrar por búsqueda
            if (_busquedaCliente.isNotEmpty) {
              final query = _busquedaCliente.toLowerCase();
              clientesOrdenados = clientesOrdenados
                  .where((c) => c.nombreRazonSocial
                      .toLowerCase()
                      .contains(query))
                  .toList();
            }
            return DropdownButtonFormField<String>(
              value: clientesOrdenados.any((c) => c.id == _clienteId)
                  ? _clienteId
                  : null,
              decoration: const InputDecoration(labelText: 'Cliente'),
              items: clientesOrdenados.map((c) {
                final vendedor = app.vendedorPorId(c.vendedorId);
                return DropdownMenuItem(
                  value: c.id,
                  child: Text(
                    '${c.nombreRazonSocial} (${vendedor?.apellido ?? ""})',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: (v) => setState(() => _clienteId = v),
            );
          }),
          const SizedBox(height: 12),

          // ── Fecha ──
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _fecha,
                firstDate: DateTime(2024),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                locale: const Locale('es'),
              );
              if (picked != null) setState(() => _fecha = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha',
                suffixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              child: Text(formatFecha(_fecha)),
            ),
          ),

          const SizedBox(height: 20),

          // ── Items (detalle de medias) ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Detalle de medias',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textSecondary)),
              Text('${_items.length} item${_items.length > 1 ? "s" : ""}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textHint)),
            ],
          ),
          const SizedBox(height: 10),

          ..._items.asMap().entries.map((entry) {
            final idx = entry.key;
            final item = entry.value;
            return _ItemCard(
              key: ValueKey('item_${idx}_$_ocrRebuildKey'),
              item: item,
              index: idx,
              canRemove: _items.length > 1,
              onRemove: () => setState(() => _items.removeAt(idx)),
              onChanged: () => setState(() {}),
            );
          }),

          // ── Agregar item ──
          OutlinedButton.icon(
            onPressed: () => setState(() => _items.add(_ItemForm())),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agregar otro tipo de carne'),
          ),

          const SizedBox(height: 20),

          // ── Totales ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _TotalRow(
                      label: 'Total kg', value: formatKg(_totalKg)),
                  const SizedBox(height: 8),
                  _TotalRow(
                    label: 'Total remito',
                    value: formatPesos(_totalPesos),
                    bold: true,
                    large: true,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Botón guardar ──
          if (!_esEdicion || app.tienePermiso('editar_remito'))
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _guardando || _clienteId == null
                    ? null
                    : _guardarRemito,
                child: _guardando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Guardar remito'),
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // SECCIÓN DE FOTO + OCR
  // ════════════════════════════════════════════
  Widget _buildFotoSection() {
    if (_leyendoOcr) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Leyendo remito...',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              const Text('Extrayendo datos de la foto',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ],
          ),
        ),
      );
    }

    if (_ocrCompletado && _fotoBytes != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // Miniatura de la foto
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  _fotoBytes!,
                  height: 100,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 16, color: AppTheme.success),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('Datos leídos del remito',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.success)),
                  ),
                  TextButton(
                    onPressed: _tomarFoto,
                    child: const Text('Otra foto',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              const Text(
                'Verificá los datos antes de guardar',
                style: TextStyle(
                    fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    // Estado inicial - sin foto
    return Card(
      child: InkWell(
        onTap: _tomarFoto,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.camera_alt_outlined,
                  size: 40, color: AppTheme.primary.withOpacity(0.6)),
              const SizedBox(height: 10),
              const Text('Sacar foto del remito',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(height: 4),
              const Text('El sistema lee los datos automáticamente',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
              if (_ocrError != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.dangerBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _ocrError!,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.danger),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text('o cargá los datos manualmente abajo',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textHint)),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  // TOMAR FOTO Y PROCESAR OCR
  // ════════════════════════════════════════════
  Future<void> _tomarFoto() async {
    final picker = ImagePicker();

    // Mostrar opciones: cámara o galería
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Seleccionar imagen',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primary.withOpacity(0.1),
                  child: const Icon(Icons.camera_alt,
                      color: AppTheme.primary),
                ),
                title: const Text('Cámara'),
                subtitle: const Text('Sacar foto del remito'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const Divider(height: 1),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppTheme.info.withOpacity(0.1),
                  child:
                      const Icon(Icons.photo_library, color: AppTheme.info),
                ),
                title: const Text('Galería'),
                subtitle: const Text('Elegir foto guardada'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final image = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      setState(() {
        _leyendoOcr = true;
        _ocrError = null;
      });

      // Leer bytes de la imagen
      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Determinar el tipo de imagen
      final extension = image.name.toLowerCase();
      String mediaType = 'image/jpeg';
      if (extension.endsWith('.png')) {
        mediaType = 'image/png';
      } else if (extension.endsWith('.webp')) {
        mediaType = 'image/webp';
      }

      setState(() => _fotoBytes = bytes);

      // Obtener credenciales de Supabase
      final supabase = Supabase.instance.client;
      final supabaseUrl = supabase.rest.url.replaceAll('/rest/v1', '');
      // Usar la anon key del cliente
      final supabaseAnonKey = supabase.rest.headers['apikey'] ?? '';

      // Llamar al OCR via Edge Function
      final resultado = await OcrService.leerRemito(
        imageBase64: base64Image,
        mediaType: mediaType,
        supabaseUrl: supabaseUrl,
        supabaseAnonKey: supabaseAnonKey,
      );

      if (resultado.error != null) {
        setState(() {
          _leyendoOcr = false;
          _ocrError = resultado.error;
          _ocrCompletado = false;
        });
        return;
      }

      // Aplicar datos del OCR al formulario
      _aplicarDatosOcr(resultado);

      setState(() {
        _leyendoOcr = false;
        _ocrCompletado = true;
        _ocrRebuildKey++; // Fuerza reconstrucción de los ItemCards
      });
    } catch (e) {
      setState(() {
        _leyendoOcr = false;
        _ocrError = 'Error: $e';
      });
    }
  }

  void _aplicarDatosOcr(OcrResult resultado) {
    final app = context.read<AppProvider>();

    // Buscar cliente por nombre
    if (resultado.clienteNombre != null) {
      final nombreBuscar = resultado.clienteNombre!.toLowerCase();
      final clienteEncontrado = app.clientes.where((c) =>
          c.nombreRazonSocial.toLowerCase().contains(nombreBuscar) ||
          nombreBuscar.contains(c.nombreRazonSocial.toLowerCase()));

      if (clienteEncontrado.isNotEmpty) {
        _clienteId = clienteEncontrado.first.id;
      }
    }

    // Parsear fecha
    if (resultado.fecha != null) {
      try {
        final partes = resultado.fecha!.split('/');
        if (partes.length == 3) {
          _fecha = DateTime(
            int.parse(partes[2]),
            int.parse(partes[1]),
            int.parse(partes[0]),
          );
        }
      } catch (_) {}
    }

    // Crear un item por cada fila del OCR
    _items.clear();

    for (final fila in resultado.filas) {
      _items.add(_ItemForm()
        ..tipoCarne = fila.tipo
        ..cantidadMedias = fila.cantMedias
        ..kg = fila.totalKg
        ..precioPorKg = fila.precioPorKg);
    }

    if (_items.isEmpty) {
      _items.add(_ItemForm());
    }
  }

  // ════════════════════════════════════════════
  // GUARDAR REMITO
  // ════════════════════════════════════════════
  Future<void> _guardarRemito() async {
    final itemsValidos = _items
        .where((i) =>
            i.tipoCarne != null &&
            i.cantidadMedias != null &&
            i.kg != null &&
            i.precioPorKg != null)
        .toList();

    if (itemsValidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Completá al menos un item del remito')),
      );
      return;
    }

    setState(() => _guardando = true);

    final Remito remito;
    final app = context.read<AppProvider>();
    final esAdmin = app.esAdmin;

    if (_esEdicion) {
      remito = widget.remitoInicial!;
      remito.clienteId = _clienteId!;
      remito.fecha = _fecha;
    } else {
      remito = Remito(
        clienteId: _clienteId!,
        fecha: _fecha,
        // Si no es admin, el remito queda pendiente de confirmación
        estado: esAdmin ? 'confirmado' : 'pendiente',
        creadoPor: app.usuarioActual?.id,
      );
    }

    final items = itemsValidos
        .map((i) => RemitoItem(
              remitoId: remito.id,
              tipoCarne: i.tipoCarne!,
              cantidadMedias: i.cantidadMedias!,
              kgTotal: i.kg!,
              precioPorKg: i.precioPorKg!,
            ))
        .toList();

    if (_esEdicion) {
      await app.actualizarRemito(remito, items);
    } else {
      await app.agregarRemito(remito, items);
    }

    setState(() => _guardando = false);

    if (mounted) {
      final mensajePendiente =
          !esAdmin && !_esEdicion ? ' (pendiente de confirmación)' : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_esEdicion
              ? 'Remito actualizado: ${formatPesos(_totalPesos)}'
              : 'Remito guardado: ${formatPesos(_totalPesos)}$mensajePendiente'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _confirmarEliminar() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar remito'),
        content: Text(
            '¿Seguro que querés eliminar el remito ${widget.remitoInicial!.numeroFormateado}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    setState(() => _guardando = true);
    final app = context.read<AppProvider>();
    await app.eliminarRemito(
      widget.remitoInicial!.id,
      eliminadoPor: app.usuarioActual?.nombreCompleto,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Remito eliminado'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context);
    }
  }
}

// ── Modelo temporal para el formulario ──
class _ItemForm {
  String? tipoCarne;
  int? cantidadMedias;
  double? kg;
  double? precioPorKg;

  double get subtotal => (kg ?? 0) * (precioPorKg ?? 0);
}

// ── Card de item individual ──
class _ItemCard extends StatelessWidget {
  final _ItemForm item;
  final int index;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  const _ItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  static const _tiposCarne = [
    'Novillo',
    'Cerdo',
    'Pollo',
    'Ternera',
    'Vaquillona',
    'Otro',
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text('Item ${index + 1}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    if (item.tipoCarne != null) ...[
                      const SizedBox(width: 8),
                      StatusPill(
                        text: item.tipoCarne!,
                        type: item.tipoCarne == 'Novillo'
                            ? StatusType.info
                            : StatusType.warning,
                      ),
                    ],
                  ],
                ),
                if (canRemove)
                  GestureDetector(
                    onTap: onRemove,
                    child: const Text('Eliminar',
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.danger)),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Tipo de carne
            DropdownButtonFormField<String>(
              value: item.tipoCarne,
              decoration: const InputDecoration(
                labelText: 'Tipo de carne',
                isDense: true,
              ),
              items: _tiposCarne
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) {
                item.tipoCarne = v;
                onChanged();
              },
            ),
            const SizedBox(height: 10),

            // Medias y Kg en fila
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: item.cantidadMedias?.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Medias',
                      isDense: true,
                    ),
                    onChanged: (v) {
                      item.cantidadMedias = int.tryParse(v);
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: item.kg?.toStringAsFixed(1),
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Kg total',
                      suffixText: 'kg',
                      isDense: true,
                    ),
                    onChanged: (v) {
                      item.kg = double.tryParse(v);
                      // Auto-detectar tipo por kg/media
                      if (item.kg != null &&
                          item.cantidadMedias != null &&
                          item.cantidadMedias! > 0) {
                        final kgPorMedia =
                            item.kg! / item.cantidadMedias!;
                        item.tipoCarne =
                            kgPorMedia > 60 ? 'Novillo' : 'Cerdo';
                      }
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Precio por kg
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: item.precioPorKg?.toStringAsFixed(0),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '\$/kg',
                      prefixText: '\$ ',
                      isDense: true,
                    ),
                    onChanged: (v) {
                      item.precioPorKg = double.tryParse(v);
                      onChanged();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Subtotal',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary)),
                        Text(
                          formatPesos(item.subtotal),
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool large;

  const _TotalRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              fontSize: bold ? 14 : 13,
              fontWeight: bold ? FontWeight.w500 : FontWeight.normal,
              color:
                  bold ? AppTheme.textPrimary : AppTheme.textSecondary,
            )),
        Text(value,
            style: TextStyle(
              fontSize: large ? 20 : 14,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}
