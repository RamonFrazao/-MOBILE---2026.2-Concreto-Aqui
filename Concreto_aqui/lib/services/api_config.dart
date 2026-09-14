/// Endereço da API. Configurável por --dart-define na hora de rodar,
/// porque "localhost" significa coisas diferentes dependendo de onde o
/// app está rodando:
///   - Emulador Android: localhost do próprio emulador ≠ localhost do PC,
///     por isso o padrão aqui é 10.0.2.2 (é como o emulador enxerga o
///     computador que o hospeda).
///   - Chrome, Windows/desktop, simulador iOS: use localhost mesmo —
///     rode com --dart-define=API_BASE_URL=http://localhost:3000
///   - Celular físico: use o IP da sua máquina na rede local —
///     --dart-define=API_BASE_URL=http://192.168.0.x:3000
class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );
}
