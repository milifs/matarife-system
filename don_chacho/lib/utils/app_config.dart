// ============================================================
// CONFIGURACIÓN POR DEPLOY
// ============================================================
// Lo que cambia entre un cliente y otro. Se puede sobreescribir en el build
// sin tocar el código:
//   flutter build web --dart-define=SOPORTE_WHATSAPP=5491122334455
// ============================================================

class AppConfig {
  /// Versión de la app. Se adjunta a cada ticket de soporte para saber
  /// contra qué build se reportó el problema.
  static const String version = 'v19.16';

  /// Nombre del cliente dueño de este deploy. Va en el mensaje de soporte
  /// para distinguir de qué instalación viene el reclamo.
  static const String clienteNombre = String.fromEnvironment(
    'CLIENTE_NOMBRE',
    defaultValue: 'Granja Don Chacho',
  );

  /// WhatsApp que recibe los reclamos de soporte, en formato internacional
  /// sin + ni espacios (Argentina celular: 549 + área sin 0 + número).
  /// Vacío = el ticket se guarda igual pero no se abre WhatsApp.
  static const String soporteWhatsapp =
      String.fromEnvironment('SOPORTE_WHATSAPP', defaultValue: '5493874159555');

  static bool get tieneWhatsappSoporte => soporteWhatsapp.trim().isNotEmpty;

  /// Si en la base ya hay RLS encendido en alguna tabla (Fase 2 de auth).
  ///
  /// Mientras sea `false`, la app trae todo como siempre: Postgres no niega
  /// nada, así que recortar las queries por permiso no protegería nada y solo
  /// cambiaría el comportamiento antes de tiempo. Se pone en `true` recién
  /// cuando se enciende el primer grupo de tablas (punto 7 de
  /// `supabase_migration_rls_politicas.sql`).
  ///
  /// **Está acá, y no como constante suelta, para poder VER la app degradada
  /// antes de encender RLS en producción:**
  ///
  ///     flutter run -d chrome --dart-define=RLS_ENCENDIDO=true
  ///
  /// Con eso, un usuario sin lectura sobre `pagos` ve lo que va a ver el día
  /// que RLS esté encendido: "no disponible" donde iba un saldo, y los
  /// formularios de pago y de nota bloqueados. Sin eso, ese camino no se puede
  /// mirar más que con tests — y lo que no se puede mirar nadie lo revisa.
  static const bool rlsEncendido =
      bool.fromEnvironment('RLS_ENCENDIDO', defaultValue: false);
}
