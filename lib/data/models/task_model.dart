import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskCategory { environment, social, personal, community, family, other }

class TaskModel {
  final String id;
  final String userId;
  final String title;
  final String description;
  final TaskCategory category;
  final int points;
  final bool isCompleted;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final DateTime? dueDate;
  final String? imageUrl;

  TaskModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    this.category = TaskCategory.other,
    this.points = 10,
    this.isCompleted = false,
    required this.createdAt,
    this.completedAt,
    this.dueDate,
    this.imageUrl,
  });

  factory TaskModel.fromMap(Map<String, dynamic> map, String id) {
    return TaskModel(
      id: id,
      userId: map['userId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      category: _parseCategoryFromString(map['category'] as String?),
      points: (map['points'] as num?)?.toInt() ?? 10,
      isCompleted: map['isCompleted'] as bool? ?? false,
      createdAt: _parseTimestamp(map['createdAt']),
      completedAt: _parseTimestamp(map['completedAt']),
      dueDate: _parseTimestamp(map['dueDate']),
      imageUrl: map['imageUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'description': description,
      'category': category.name,
      'points': points,
      'isCompleted': isCompleted,
      'createdAt': Timestamp.fromDate(createdAt ?? DateTime.now()),
      'completedAt':
          completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'imageUrl': imageUrl,
    };
  }

  TaskModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    TaskCategory? category,
    int? points,
    bool? isCompleted,
    DateTime? createdAt,
    DateTime? completedAt,
    DateTime? dueDate,
    String? imageUrl,
  }) {
    return TaskModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      points: points ?? this.points,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      dueDate: dueDate ?? this.dueDate,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static TaskCategory _parseCategoryFromString(String? value) {
    if (value == null) return TaskCategory.other;
    try {
      return TaskCategory.values.firstWhere(
        (e) => e.name == value,
        orElse: () => TaskCategory.other,
      );
    } catch (e) {
      return TaskCategory.other;
    }
  }

  // Pomocnicze gettery
  String get categoryDisplayName {
    switch (category) {
      case TaskCategory.environment:
        return 'Środowisko';
      case TaskCategory.social:
        return 'Społeczne';
      case TaskCategory.personal:
        return 'Osobiste';
      case TaskCategory.community:
        return 'Społeczność';
      case TaskCategory.family:
        return 'Rodzina';
      case TaskCategory.other:
        return 'Inne';
    }
  }

  bool get isOverdue {
    if (dueDate == null || isCompleted) return false;
    return DateTime.now().isAfter(dueDate!);
  }

  bool get isDueToday {
    if (dueDate == null || isCompleted) return false;
    final now = DateTime.now();
    return dueDate!.year == now.year &&
        dueDate!.month == now.month &&
        dueDate!.day == now.day;
  }
}
