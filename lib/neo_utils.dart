Map<String, dynamic> asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
  return <String, dynamic>{};
}

/* Map<String, dynamic> asMap(dynamic value) {
  if (value == null || value is! Map) {
    return {};
  }
  return Map<String, dynamic>.from(value);
} */

List<dynamic> asList(dynamic value) {
  if (value is List) return value;
  return <dynamic>[];
}

/* List<dynamic> asList(dynamic value) {
  if (value == null || value is! List) {
    return [];
  }
  return value;
} */

String asString(dynamic value) {
  if (value == null) return '';
  return value.toString();
}

int asInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

/* int asInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
} */

double asDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

/* double asDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0;
} */

bool asBool(dynamic value) {
  if (value is bool) return value;
  if (value == null) return false;
  return value.toString().toLowerCase() == 'true';
}

/* bool asBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is int) return value == 1;
  if (value is String) {
    return value.toLowerCase() == 'true' || value == '1';
  }
  return false;
}*/
