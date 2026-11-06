import 'package:cloud_firestore/cloud_firestore.dart';

/// Model một thẻ công việc: `boards/{boardId}/cards/{cardId}`.
///
/// Tên trường theo § 4.7 của `docs/firestore-schema.md`. Bộ đếm
/// `commentCount`, `checklistTotal`, `checklistDone` nằm sẵn trong card để vẽ
/// thẻ tóm tắt mà không phải đọc dữ liệu con (quyết định D4).
class TaskCardModel {
  const TaskCardModel({
    required this.id,
    required this.boardId,
    required this.listId,
    required this.title,
    required this.position,
    required this.createdBy,
    this.description = '',
    this.isCompleted = false,
    this.assigneeIds = const [],
    this.labelIds = const [],
    this.dueAt,
    this.archivedAt,
    this.commentCount = 0,
    this.checklistTotal = 0,
    this.checklistDone = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// ID board cha, không đổi (phục vụ truy vấn xuyên board của UC07).
  final String boardId;

  /// ID list hiện tại, luôn thuộc cùng board.
  final String listId;

  /// Tiêu đề 1–200 ký tự (đã trim khi ghi).
  final String title;
  final String description;

  /// Thứ tự trong list, sắp xếp tăng dần.
  final double position;
  final bool isCompleted;
  final List<String> assigneeIds;
  final List<String> labelIds;
  final DateTime? dueAt;

  /// `null` khi card đang hiển thị trên board.
  final DateTime? archivedAt;
  final int commentCount;
  final int checklistTotal;
  final int checklistDone;

  /// uid người tạo, không đổi.
  final String createdBy;

  /// Giờ máy chủ; `null` trong lúc thao tác tạo chưa được máy chủ xác nhận.
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isArchived => archivedAt != null;

  factory TaskCardModel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return TaskCardModel(
      id: document.id,
      boardId: data['boardId'] as String? ?? '',
      listId: data['listId'] as String? ?? '',
      title: data['title'] as String? ?? '(Chưa có tiêu đề)',
      description: data['description'] as String? ?? '',
      position: (data['position'] as num?)?.toDouble() ?? 0.0,
      isCompleted: data['isCompleted'] as bool? ?? false,
      assigneeIds: _toStringList(data['assigneeIds']),
      labelIds: _toStringList(data['labelIds']),
      dueAt: _toDateTime(data['dueAt']),
      archivedAt: _toDateTime(data['archivedAt']),
      commentCount: (data['commentCount'] as num?)?.toInt() ?? 0,
      checklistTotal: (data['checklistTotal'] as num?)?.toInt() ?? 0,
      checklistDone: (data['checklistDone'] as num?)?.toInt() ?? 0,
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: _toDateTime(data['createdAt']),
      updatedAt: _toDateTime(data['updatedAt']),
    );
  }

  /// Bản sao có thay đổi; dùng cho repository giả trong preview và test.
  TaskCardModel copyWith({
    String? listId,
    String? title,
    double? position,
    bool? isCompleted,
    DateTime? archivedAt,
    DateTime? updatedAt,
  }) {
    return TaskCardModel(
      id: id,
      boardId: boardId,
      listId: listId ?? this.listId,
      title: title ?? this.title,
      description: description,
      position: position ?? this.position,
      isCompleted: isCompleted ?? this.isCompleted,
      assigneeIds: assigneeIds,
      labelIds: labelIds,
      dueAt: dueAt,
      archivedAt: archivedAt ?? this.archivedAt,
      commentCount: commentCount,
      checklistTotal: checklistTotal,
      checklistDone: checklistDone,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Thứ tự hiển thị trong list: `position`, rồi `createdAt` khi hai người
  /// kéo thả cùng lúc tạo ra vị trí trùng nhau (access patterns § 5).
  static int compare(TaskCardModel a, TaskCardModel b) {
    final byPosition = a.position.compareTo(b.position);
    if (byPosition != 0) return byPosition;
    // Card vừa tạo chưa có giờ máy chủ được xếp sau cùng.
    final aCreated = a.createdAt;
    final bCreated = b.createdAt;
    if (aCreated != null && bCreated != null) {
      final byCreated = aCreated.compareTo(bCreated);
      if (byCreated != 0) return byCreated;
    } else if (aCreated != bCreated) {
      return aCreated == null ? 1 : -1;
    }
    return a.id.compareTo(b.id);
  }

  static List<String> _toStringList(Object? value) =>
      (value as List<dynamic>? ?? const []).whereType<String>().toList(
        growable: false,
      );

  static DateTime? _toDateTime(Object? value) {
    if (value is Timestamp) return value.toDate();
    return null;
  }

  @override
  String toString() =>
      'TaskCardModel(id: $id, listId: $listId, title: $title, '
      'position: $position, isCompleted: $isCompleted)';
}

/// Nhãn màu của board: `boards/{boardId}/labels/{labelId}`.
class CardLabel {
  const CardLabel({required this.id, required this.name, required this.color});

  final String id;
  final String name;

  /// Màu ARGB, đọc từ chuỗi `#RRGGBB`.
  final int color;

  factory CardLabel.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return CardLabel(
      id: document.id,
      name: data['name'] as String? ?? '',
      color: parseHexColor(data['color'] as String?),
    );
  }

  /// Chuyển `#RRGGBB` thành ARGB; màu xám nếu sai định dạng.
  static int parseHexColor(String? hex) {
    final value = int.tryParse(hex?.replaceFirst('#', '') ?? '', radix: 16);
    if (hex == null || hex.length != 7 || value == null) return 0xFF9E9E9E;
    return 0xFF000000 | value;
  }
}

/// Thành viên board để hiển thị avatar: `boards/{boardId}/members/{uid}`.
class BoardMember {
  const BoardMember({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
  });

  final String uid;
  final String displayName;
  final String email;

  /// `owner` hoặc `member`.
  final String role;

  /// Chữ cái đầu của tên gọi (từ cuối trong họ tên tiếng Việt).
  String get initial {
    final words = displayName.trim().split(RegExp(r'\s+'));
    final name = words.isEmpty || words.last.isEmpty ? email : words.last;
    return name.isEmpty
        ? '?'
        : String.fromCharCode(name.runes.first).toUpperCase();
  }

  factory BoardMember.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};
    return BoardMember(
      uid: document.id,
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String? ?? '',
      role: data['role'] as String? ?? 'member',
    );
  }
}

/// Toàn bộ card chưa lưu trữ của một board, kèm trạng thái đồng bộ.
class BoardCardsSnapshot {
  BoardCardsSnapshot({
    required List<TaskCardModel> cards,
    this.isFromCache = false,
  }) : cards = List.unmodifiable(
         List<TaskCardModel>.of(cards)..sort(TaskCardModel.compare),
       );

  /// Card đã sắp xếp theo thứ tự hiển thị.
  final List<TaskCardModel> cards;

  /// `true` khi dữ liệu lấy từ bộ nhớ đệm vì không kết nối được Firestore.
  final bool isFromCache;

  late final Map<String, List<TaskCardModel>> _byList = () {
    final grouped = <String, List<TaskCardModel>>{};
    for (final card in cards) {
      grouped.putIfAbsent(card.listId, () => []).add(card);
    }
    return grouped;
  }();

  /// Card của một list, theo thứ tự hiển thị.
  List<TaskCardModel> cardsInList(String listId) => _byList[listId] ?? const [];
}
