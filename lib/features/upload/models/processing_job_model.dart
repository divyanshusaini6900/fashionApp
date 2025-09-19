enum JobStatus {
  pending,
  processing,
  completed,
  failed,
}

class ProcessingJob {
  final String id;
  final String userId;
  final String? skuId;
  final JobStatus status;
  final double progress;
  final String message;
  final Map<String, dynamic>? result;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? errorMessage;

  ProcessingJob({
    required this.id,
    required this.userId,
    this.skuId,
    required this.status,
    required this.progress,
    required this.message,
    this.result,
    required this.createdAt,
    this.completedAt,
    this.errorMessage,
  });

  factory ProcessingJob.fromJson(Map<String, dynamic> json) {
    return ProcessingJob(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? json['userId'] ?? '',
      skuId: json['skuId'] ?? json['sku_id'],
      status: JobStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => JobStatus.pending,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      message: json['message'] ?? '',
      result: json['result'] != null ? Map<String, dynamic>.from(json['result']) : null,
      createdAt: _parseDateTime(json['created_at'] ?? json['createdAt']) ?? DateTime.now(),
      completedAt: _parseDateTime(json['completed_at'] ?? json['completedAt']),
      errorMessage: json['error_message'] ?? json['errorMessage'],
    );
  }
  
  /// Helper method to parse DateTime from various formats (String, Timestamp, etc.)
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    
    try {
      // Handle Firebase Timestamp - check if it has toDate method
      if (value != null && value.runtimeType.toString().contains('Timestamp')) {
        try {
          return (value as dynamic).toDate() as DateTime;
        } catch (e) {
          print('Error converting Timestamp: $e');
        }
      }
      
      // Handle String
      if (value is String && value.isNotEmpty) {
        return DateTime.parse(value);
      }
      
      // Handle DateTime (already parsed)
      if (value is DateTime) {
        return value;
      }
      
      // Handle milliseconds since epoch
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      
      // Handle Map (Firebase Timestamp as Map)
      if (value is Map && value.containsKey('_seconds')) {
        final seconds = value['_seconds'] as int;
        final nanoseconds = (value['_nanoseconds'] as int?) ?? 0;
        return DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000 + (nanoseconds / 1000000).round()
        );
      }
      
    } catch (e) {
      print('Error parsing DateTime: $e for value: $value (type: ${value.runtimeType})');
    }
    
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'skuId': skuId,
      'status': status.toString().split('.').last,
      'progress': progress,
      'message': message,
      'result': result,
      'created_at': createdAt.toIso8601String(),
      'completed_at': completedAt?.toIso8601String(),
      'error_message': errorMessage,
    };
  }

  bool get isCompleted => status == JobStatus.completed;
  bool get isFailed => status == JobStatus.failed;
  bool get isProcessing => status == JobStatus.processing;
}
