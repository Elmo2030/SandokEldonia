/// Errors of the Xtream / M3U layer. Compare with `==` (e.g. `IPTVError.http(403)`).
class IPTVError implements Exception {
  const IPTVError._(this._name, [this.code]);

  static const badResponse = IPTVError._('badResponse');
  static const badConfig = IPTVError._('badConfig');
  static const badCredentials = IPTVError._('badCredentials');
  static const emptyResponse = IPTVError._('emptyResponse');
  static const accountInactive = IPTVError._('accountInactive');
  static IPTVError http(int code) => IPTVError._('http', code);

  final String _name;

  /// The HTTP status, for `IPTVError.http`.
  final int? code;

  /// English text for logs; the app shows its own translation.
  String get description => switch (_name) {
        'http' => 'HTTP $code',
        'badResponse' => 'Unexpected response from server',
        'badConfig' => 'Invalid server address',
        'badCredentials' => 'Wrong username or password',
        'emptyResponse' => 'The server returned an empty list; keeping your saved data',
        _ => 'The subscription is not active (expired or disabled)',
      };

  @override
  bool operator ==(Object other) => other is IPTVError && other._name == _name && other.code == code;

  @override
  int get hashCode => Object.hash(_name, code);

  @override
  String toString() => 'IPTVError($description)';
}
