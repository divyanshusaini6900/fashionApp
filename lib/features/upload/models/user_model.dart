class UserModel {
  final String id;
  final String username;
  final String? email;
  final DateTime createdAt;
  final String? companyName;

  UserModel({
    required this.id,
    required this.username,
    this.email,
    required this.createdAt,
    this.companyName,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'created_at': createdAt.toIso8601String(),
      'company_name': companyName,
    };
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      createdAt: DateTime.parse(json['created_at']),
      companyName: json['company_name'],
    );
  }

  UserModel copyWith({
    String? id,
    String? username,
    String? email,
    DateTime? createdAt,
    String? companyName,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      companyName: companyName ?? this.companyName,
    );
  }
}
