// ============================================================
// DESGLOSE DE LOS KG DE LA SEMANA - a quién se le vendió (v19.10)
// ============================================================
// Lo que hay detrás del número grande de kg del dashboard: los clientes que
// se llevaron esa carne, cuántas medias cada uno y por cuánta plata.
//
// Los números son SOLO los del tipo que se tocó en el dashboard (novillo o
// cerdo). Un remito puede traer los dos; en ese caso se muestra aparte el
// total de la factura, que es lo único que no coincide con la parte.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../utils/theme.dart';

class DetalleKgSemanaScreen extends StatelessWidget {
  /// 'Novillo' o 'Cerdo'.
  final String tipo;
  final DateTime semana;

  /// Viene del ojo del dashboard: si los valores están ocultos allá, también
  /// lo están acá. El toggle es para mostrar la pantalla sin los números.
  final bool ofuscado;

  const DetalleKgSemanaScreen({
    super.key,
    required this.tipo,
    required this.semana,
    this.ofuscado = false,
  });

  String _ocultar(String valor) => ofuscado ? '••••' : valor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tipo, style: const TextStyle(fontSize: 18)),
            Text(
              'Semana ${formatRangoSemana(semana)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: Consumer<AppProvider>(
        builder: (context, app, _) {
          final desglose = app.desgloseVentasSemana(tipo, semana);

          if (desglose.vacio) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inbox_outlined,
                        size: 40, color: AppTheme.textHint),
                    const SizedBox(height: 12),
                    Text('No se vendió ${tipo.toLowerCase()} esta semana',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    const Text('Solo cuentan los remitos confirmados',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _Total(
                          label: 'Kg',
                          valor: _ocultar(formatKg(desglose.kg)),
                        ),
                      ),
                      Expanded(
                        child: _Total(
                          label: 'Medias',
                          valor: _ocultar('${desglose.medias}'),
                        ),
                      ),
                      Expanded(
                        child: _Total(
                          label: 'Facturado',
                          valor: _ocultar(formatPesos(desglose.importe)),
                          color: AppTheme.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                      '${desglose.cantidadClientes} '
                      '${desglose.cantidadClientes == 1 ? 'cliente' : 'clientes'}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textSecondary)),
                  Text(
                      '${desglose.cantidadRemitos} '
                      '${desglose.cantidadRemitos == 1 ? 'remito' : 'remitos'}',
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.textHint)),
                ],
              ),
              const SizedBox(height: 10),
              ...desglose.clientes.map((c) => _ClienteCard(
                    venta: c,
                    ofuscado: ofuscado,
                  )),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

// ── Widgets internos ──

class _Total extends StatelessWidget {
  final String label;
  final String valor;
  final Color color;

  const _Total({
    required this.label,
    required this.valor,
    this.color = AppTheme.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(valor,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: color)),
        ),
      ],
    );
  }
}

/// Un cliente del desglose: el resumen siempre visible y, al desplegarlo,
/// los remitos que lo componen.
class _ClienteCard extends StatelessWidget {
  final VentaClienteSemana venta;
  final bool ofuscado;

  const _ClienteCard({required this.venta, required this.ofuscado});

  String _ocultar(String valor) => ofuscado ? '••••' : valor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Theme(
        // El ExpansionTile dibuja una línea arriba y abajo que pelea con el
        // borde de la Card.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          // Los kg y el importe van en el título y no en el `trailing`: ese
          // lugar es el de la flechita de desplegar, y sin ella la tarjeta
          // no parece que se pueda abrir.
          title: Row(
            children: [
              Expanded(
                child: Text(venta.clienteNombre,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_ocultar(formatKg(venta.kg)),
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_ocultar(formatPesos(venta.importe)),
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.success)),
                ],
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              [
                if (venta.vendedorNombre != null) venta.vendedorNombre!,
                '${venta.medias} ${venta.medias == 1 ? 'media' : 'medias'}',
                '${venta.cantidadRemitos} '
                    '${venta.cantidadRemitos == 1 ? 'remito' : 'remitos'}',
              ].join(' · '),
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          children: [
            for (final r in venta.remitos) _filaRemito(r),
            if (venta.hayRemitosMezclados) ...[
              const SizedBox(height: 8),
              const Text(
                'Los remitos con "Factura completa" traen además otro tipo '
                'de carne: acá se cuenta solo esta parte.',
                style: TextStyle(fontSize: 11, color: AppTheme.textHint),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filaRemito(VentaRemitoSemana r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${r.remito.numeroFormateado} · '
                    '${formatFecha(r.remito.fecha)}',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                    '${r.medias} ${r.medias == 1 ? 'media' : 'medias'} · '
                    '${_ocultar(formatKg(r.kg))}',
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary)),
                if (r.tieneOtrosTipos)
                  Text(
                      'Factura completa: '
                      '${_ocultar(formatPesos(r.totalFactura))}',
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textHint)),
              ],
            ),
          ),
          Text(_ocultar(formatPesos(r.importe)),
              style: const TextStyle(fontSize: 13, color: AppTheme.success)),
        ],
      ),
    );
  }
}
