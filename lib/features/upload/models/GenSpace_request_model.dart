class GenSpaceRequest {
  final String userId;
  final List<Map<String, dynamic>> products;
  final DateTime timestamp;

  GenSpaceRequest({
    required this.userId,
    required this.products,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'products': products,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory GenSpaceRequest.fromJson(Map<String, dynamic> json) {
    return GenSpaceRequest(
      userId: json['user_id'],
      products: List<Map<String, dynamic>>.from(
        (json['products'] as List).map((e) => Map<String, dynamic>.from(e)),
      ),
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}
