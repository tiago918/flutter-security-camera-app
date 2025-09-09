class Credentials {
  final String username;
  final String password;
  final String? domain;
  final DateTime? expiresAt;
  final Map<String, String> additionalHeaders;

  const Credentials({
    required this.username,
    required this.password,
    this.domain,
    this.expiresAt,
    this.additionalHeaders = const {},
  });

  factory Credentials.fromJson(Map<String, dynamic> json) {
    return Credentials(
      username: json['username'] as String,
      password: json['password'] as String,
      domain: json['domain'] as String?,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      additionalHeaders: Map<String, String>.from(
          json['additionalHeaders'] as Map<String, dynamic>? ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'password': password,
      'domain': domain,
      'expiresAt': expiresAt?.toIso8601String(),
      'additionalHeaders': additionalHeaders,
    };
  }

  Credentials copyWith({
    String? username,
    String? password,
    String? domain,
    DateTime? expiresAt,
    Map<String, String>? additionalHeaders,
  }) {
    return Credentials(
      username: username ?? this.username,
      password: password ?? this.password,
      domain: domain ?? this.domain,
      expiresAt: expiresAt ?? this.expiresAt,
      additionalHeaders: additionalHeaders ?? this.additionalHeaders,
    );
  }

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(expiresAt!);
  }

  String get basicAuthHeader {
    final credentials = '$username:$password';
    final encoded = base64Encode(utf8.encode(credentials));
    return 'Basic $encoded';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Credentials &&
        other.username == username &&
        other.password == password &&
        other.domain == domain;
  }

  @override
  int get hashCode => Object.hash(username, password, domain);

  @override
  String toString() {
    return 'Credentials(username: $username, domain: $domain)';
  }
}

// Imports necessários
import 'dart:convert';
import 'dart:typed_data';