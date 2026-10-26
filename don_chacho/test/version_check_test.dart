// Fija cuándo se le avisa al usuario que hay una versión nueva.
//
// Lo importante acá es lo que NO dispara el aviso. Recargar le tira al
// usuario lo que tenga a medio cargar, así que un aviso de más (por estar sin
// internet, o porque el archivo todavía no existe en el servidor) es peor que
// uno de menos.

import 'package:flutter_test/flutter_test.dart';
import 'package:don_chacho_matarife/utils/version_check.dart';

void main() {
  test('versiones distintas: hay que avisar', () {
    expect(
      hayVersionNueva(corriendo: 'v19.3', publicada: 'v19.4'),
      isTrue,
    );
  });

  test('la misma versión: no se avisa nada', () {
    expect(
      hayVersionNueva(corriendo: 'v19.3', publicada: 'v19.3'),
      isFalse,
    );
  });

  test('un rollback también pide recargar', () {
    // La publicada es MENOR que la que está corriendo. Igual hay que
    // recargar: el usuario tiene un bundle que ya no es el de producción.
    // Por eso la comparación es por igualdad y no por "mayor que".
    expect(
      hayVersionNueva(corriendo: 'v19.4', publicada: 'v19.3'),
      isTrue,
    );
  });

  group('no se avisa cuando no se sabe', () {
    test('sin respuesta del servidor (sin internet, 404)', () {
      expect(
        hayVersionNueva(corriendo: 'v19.3', publicada: null),
        isFalse,
      );
    });

    test('el servidor contestó un string vacío', () {
      expect(
        hayVersionNueva(corriendo: 'v19.3', publicada: ''),
        isFalse,
      );
      expect(
        hayVersionNueva(corriendo: 'v19.3', publicada: '   '),
        isFalse,
      );
    });

    test('el bundle se compiló sin versión', () {
      expect(
        hayVersionNueva(corriendo: '', publicada: 'v19.4'),
        isFalse,
      );
    });
  });

  test('los espacios de más no cuentan como versión distinta', () {
    // Que un \n al final del JSON no dispare un aviso falso en cada chequeo.
    expect(
      hayVersionNueva(corriendo: 'v19.3', publicada: ' v19.3\n'),
      isFalse,
    );
  });
}
