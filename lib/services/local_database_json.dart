import 'dart:convert';

Map<String, dynamic> decodeLocalJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Invalid legacy JSON is treated as an empty value.
    }
  }
  return {};
}

List<dynamic> decodeLocalJsonList(Object? value) {
  var decoded = value;
  for (var attempt = 0; attempt < 3; attempt++) {
    if (decoded is List<dynamic>) return decoded;
    if (decoded is! String) return [];
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      return [];
    }
  }
  return [];
}
