import 'dart:convert';

/// Utilities for decoding and verifying JWT tokens without third-party dependencies.
class JwtUtils {
  /// Decodes the payload portion of a JWT string.
  static Map<String, dynamic>? decodePayload(String token) {
    try {
      final clean = token.trim();
      final parts = clean.split('.');
      if (parts.length != 3) return null;

      var normalized = base64Url.normalize(parts[1]);
      final payloadString = utf8.decode(base64Url.decode(normalized));
      final decoded = jsonDecode(payloadString);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Extracts the expiration date/time from the token, if present.
  static DateTime? getExpiry(String token) {
    final payload = decodePayload(token);
    if (payload == null || !payload.containsKey('exp')) return null;
    final exp = payload['exp'];
    if (exp is int) {
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    }
    return null;
  }

  /// Returns true if the token is already expired or will expire in less than [bufferSeconds].
  static bool isExpired(String token, {int bufferSeconds = 0}) {
    final expiry = getExpiry(token);
    if (expiry == null) return false;
    return DateTime.now().add(Duration(seconds: bufferSeconds)).isAfter(expiry);
  }

  /// Attempts to extract a user-identifying label (name, email, or sub).
  static String? getUserIdentifier(String token) {
    final payload = decodePayload(token);
    if (payload == null) return null;

    if (payload['name'] is String && (payload['name'] as String).isNotEmpty) {
      return payload['name'] as String;
    }
    if (payload['email'] is String && (payload['email'] as String).isNotEmpty) {
      return payload['email'] as String;
    }
    if (payload['sub'] is String && (payload['sub'] as String).isNotEmpty) {
      final sub = payload['sub'] as String;
      // Truncate long auth0 sub like auth0|123456
      return sub.startsWith('auth0|') ? sub.substring(6) : sub;
    }
    return null;
  }

  /// Returns a human-friendly string describing the expiry state.
  static String formatExpiryStatus(String token) {
    final expiry = getExpiry(token);
    if (expiry == null) {
      return 'No expiry date in token';
    }

    final now = DateTime.now();
    final difference = expiry.difference(now);

    if (difference.isNegative) {
      final past = now.difference(expiry);
      if (past.inDays > 0) {
        return 'Expired ${past.inDays}d ago';
      } else if (past.inHours > 0) {
        return 'Expired ${past.inHours}h ago';
      } else if (past.inMinutes > 0) {
        return 'Expired ${past.inMinutes}m ago';
      } else {
        return 'Expired just now';
      }
    } else {
      if (difference.inDays > 0) {
        return 'Valid for ${difference.inDays}d ${difference.inHours % 24}h';
      } else if (difference.inHours > 0) {
        return 'Valid for ${difference.inHours}h ${difference.inMinutes % 60}m';
      } else if (difference.inMinutes > 0) {
        return 'Valid for ${difference.inMinutes}m';
      } else {
        return 'Expires in <1m';
      }
    }
  }
}
