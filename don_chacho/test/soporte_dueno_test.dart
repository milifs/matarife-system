// De quién es un ticket de soporte (Fase 2 de auth).
//
// Hasta v19.15 el dueño era `reportado_por`, que es TEXT con el nombre
// completo. No aguanta una política de RLS: `nombre_completo` no es único,
// renombrar a alguien le borra su historia y el match depende de tildes y
// mayúsculas. Desde v19.16 el dueño es `reportado_por_id`, que apunta al
// perfil, y **la app filtra por lo mismo que la política**.

import 'package:flutter_test/flutter_test.dart';

import 'package:don_chacho_matarife/models/models.dart';

void main() {
  group('toMap', () {
    test('manda reportado_por_id cuando el ticket tiene dueño', () {
      // Es el campo que mira `soportes_insert`: si no viaja, con RLS
      // encendido el insert se rechaza y nadie puede reportar nada.
      final t = TicketSoporte(
        modulo: 'Depósito',
        descripcion: 'Quedó en -10 medias',
        reportadoPor: 'Rocío López',
        reportadoPorId: 'perfil-1',
      );
      expect(t.toMap()['reportado_por_id'], 'perfil-1');
    });

    test('sigue mandando el nombre, que es lo que se muestra', () {
      // El texto no se reemplaza: es lo que ve el admin en la bandeja y lo
      // único que tienen los tickets viejos sin vincular.
      final t = TicketSoporte(reportadoPor: 'Rocío López');
      expect(t.toMap()['reportado_por'], 'Rocío López');
    });

    test('no manda la columna si el ticket no tiene dueño', () {
      // Mandar un null explícito no agrega nada y haría ruido en el insert.
      final t = TicketSoporte(modulo: 'Remitos', descripcion: 'x');
      expect(t.toMap().containsKey('reportado_por_id'), isFalse);
    });
  });

  group('fromMap', () {
    test('lee el id del dueño', () {
      final t = TicketSoporte.fromMap({
        'id': 'ticket-1',
        'numero': 7,
        'modulo': 'Pagos',
        'descripcion': 'No guarda',
        'reportado_por': 'Soledad Alcalá',
        'reportado_por_id': 'perfil-2',
        'creado_en': '2026-10-30T09:00:00.000',
      });
      expect(t.reportadoPorId, 'perfil-2');
      expect(t.tieneDueno, isTrue);
    });

    test('tolera que la columna todavía no exista', () {
      // La migración 24 va antes del deploy, pero leer no tiene por qué
      // romperse si el orden se invierte: un ticket sin la columna se lee
      // como un ticket sin vincular, no como una excepción.
      final t = TicketSoporte.fromMap({
        'id': 'ticket-2',
        'modulo': 'Reparto',
        'descripcion': 'y',
        'reportado_por': 'Joaco',
        'creado_en': '2026-10-30T09:00:00.000',
      });
      expect(t.reportadoPorId, isNull);
      expect(t.tieneDueno, isFalse);
      // El nombre sigue estando: es lo que la bandeja muestra.
      expect(t.reportadoPor, 'Joaco');
    });

    test('un ticket viejo sin vincular no se confunde con uno nuevo', () {
      // `tieneDueno` es lo que la bandeja usa para avisarle al admin que su
      // respuesta no le va a aparecer al autor en "mis últimos reclamos".
      final viejo = TicketSoporte.fromMap({
        'id': 'v',
        'modulo': 'Soporte',
        'descripcion': 'z',
        'reportado_por_id': null,
        'creado_en': '2026-09-01T09:00:00.000',
      });
      expect(viejo.tieneDueno, isFalse);
    });
  });
}
