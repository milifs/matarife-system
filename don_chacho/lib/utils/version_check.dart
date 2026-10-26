// ============================================================
// COMPARACIÓN DE VERSIONES (v19.4)
// ============================================================
// La decisión de "¿hay que avisar que salió una versión nueva?" vive acá
// sola, sin nada de web, para poder testearla. El que sale a buscar la
// versión publicada y el que recarga la página son `version_service.dart`,
// que es web-only.
//
// La comparación es por IGUALDAD, no por "mayor que". No se intenta ordenar
// v19.10 contra v19.9 ni nada por el estilo: alcanza con que el string del
// servidor sea distinto al compilado para saber que el navegador está
// corriendo algo viejo. Eso también cubre el caso raro de un rollback, donde
// la versión publicada es MENOR y el usuario igual tiene que recargar.

/// ¿El navegador está corriendo algo distinto a lo que hay publicado?
///
/// [corriendo] es `AppConfig.version` (lo que se compiló en este bundle).
/// [publicada] es lo que dice `app_version.json` en el servidor; viene null
/// si no se pudo consultar (sin internet, archivo que todavía no existe).
///
/// Ante cualquier duda devuelve false: un aviso de más es peor que uno de
/// menos, porque el usuario pierde lo que estaba cargando al recargar.
bool hayVersionNueva({
  required String corriendo,
  required String? publicada,
}) {
  if (publicada == null) return false;

  final pub = publicada.trim();
  final cor = corriendo.trim();

  if (pub.isEmpty || cor.isEmpty) return false;

  return pub != cor;
}
