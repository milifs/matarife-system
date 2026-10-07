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
  static const String version = 'v18.37';

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
}
