// Identidad de Supabase Auth (Fase 1).
//
// Se prueba lo que se puede probar sin red: el armado del mail sintético y la
// lectura/escritura del vínculo `auth_id` en el modelo. El login en sí sale a
// Supabase, así que no entra acá.
//
// `AuthService.mailDe` y las constantes no tocan `Supabase.instance.client`:
// en Dart los campos estáticos se inicializan la primera vez que se LEEN, y
// este test nunca lee `_client`.

import 'package:flutter_test/flutter_test.dart';

import 'package:don_chacho_matarife/models/models.dart';
import 'package:don_chacho_matarife/services/auth_service.dart';

void main() {
  group('mail sintético', () {
    test('el usuario se convierte en mail con el dominio reservado', () {
      expect(AuthService.mailDe('rociolopez'),
          'rociolopez@${AuthService.dominioSintetico}');
    });

    test('normaliza espacios y mayúsculas igual que el login', () {
      // El login hace `trim().toLowerCase()` antes de buscar. Si el mail se
      // armara distinto, "  RocioLopez " entraría por el legacy y nunca por
      // su cuenta de Auth: el usuario parecería andar y en realidad no
      // tendría sesión de Supabase.
      expect(AuthService.mailDe('  RocioLopez '),
          AuthService.mailDe('rociolopez'));
    });

    test('el dominio no es de internet', () {
      // `.local` no se resuelve en internet a propósito: estas cuentas no son
      // casillas y nadie tiene que poder mandarles un mail de recupero.
      expect(AuthService.dominioSintetico.endsWith('.local'), isTrue);
    });
  });

  group('Usuario y el vínculo con la identidad', () {
    Map<String, dynamic> fila({String? authId}) => {
          'id': 'f132cb54-cf89-4cdd-9814-0e444c5751ef',
          'usuario': 'rociolopez',
          'password_hash': 'abc',
          'rol_id': '00000000-0000-0000-0000-000000000002',
          'nombre_completo': 'Rocio Lopez',
          'activo': true,
          if (authId != null) 'auth_id': authId,
          'creado_en': '2026-04-22T17:15:24.920Z',
        };

    test('lee auth_id cuando la fila lo trae', () {
      final u = Usuario.fromMap(fila(authId: 'aaaaaaaa-0000-0000-0000-000000000001'));
      expect(u.authId, 'aaaaaaaa-0000-0000-0000-000000000001');
      expect(u.tieneCuentaDeAuth, isTrue);
    });

    test('sin la columna cae en "sin cuenta" en vez de romper', () {
      // Cubre la ventana entre deployar la app y correr la migración: la
      // columna no existe todavía y la app tiene que entrar igual.
      final u = Usuario.fromMap(fila());
      expect(u.authId, isNull);
      expect(u.tieneCuentaDeAuth, isFalse);
    });

    test('auth_id null explícito es "sin cuenta"', () {
      final u = Usuario.fromMap({...fila(), 'auth_id': null});
      expect(u.tieneCuentaDeAuth, isFalse);
    });

    test('toMap NO manda auth_id', () {
      // Es la protección que importa: Gestión de Usuarios arma un `Usuario`
      // nuevo con los campos del formulario, sin auth_id. Si `toMap()` lo
      // mandara, guardar a alguien para cambiarle el rol le borraría el
      // vínculo y lo dejaría afuera de la app sin que nadie se entere.
      final u = Usuario.fromMap(fila(authId: 'aaaaaaaa-0000-0000-0000-000000000001'));
      expect(u.toMap().containsKey('auth_id'), isFalse);
    });
  });
}
