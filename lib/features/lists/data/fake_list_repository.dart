import 'dart:async';

import 'list_model.dart';
import 'list_repository.dart';

// ---------------------------------------------------------------------------
// Internal in-memory record (không expose ra ngoài)
// ---------------------------------------------------------------------------

/// Bản ghi nội bộ của FakeListRepository.
///
/// Card nằm riêng trong `FakeCardRepository`; board chỉ hiện card thuộc list
/// đang hoạt động nên card của list đã lưu trữ cũng bị ẩn theo.
class _ListRecord {
  _ListRecord({required this.model});

  TaskListModel model;
}

// ---------------------------------------------------------------------------
// FakeListRepository
// ---------------------------------------------------------------------------

/// Triển khai [ListRepository] hoàn toàn trong bộ nhớ (in-memory).
///
/// Phục vụ:
/// 1. Preview mode khi chưa cấu hình Firebase.
/// 2. Unit testing mà không cần mock/stub Firestore.
class FakeListRepository implements ListRepository {
  FakeListRepository() {
    _seed();
  }

  // Lưu trữ nội bộ: boardId -> danh sách _ListRecord
  final Map<String, List<_ListRecord>> _store = {};

  // Một StreamController broadcast cho mỗi boardId đang được theo dõi
  final Map<String, StreamController<List<TaskListModel>>> _controllers = {};
  final Map<String, StreamController<List<TaskListModel>>>
  _archivedControllers = {};

  // ---------------------------------------------------------------------------
  // Seed data
  // ---------------------------------------------------------------------------

  void _seed() {
    const boardId = 'thesis_board';
    _store[boardId] = [
      _ListRecord(
        model: TaskListModel(
          id: 'list_todo',
          name: 'Cần làm',
          position: 1000.0,
          archivedAt: null,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 1),
        ),
      ),
      _ListRecord(
        model: TaskListModel(
          id: 'list_doing',
          name: 'Đang làm',
          position: 2000.0,
          archivedAt: null,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 5),
        ),
      ),
      _ListRecord(
        model: TaskListModel(
          id: 'list_done',
          name: 'Hoàn thành',
          position: 3000.0,
          archivedAt: null,
          createdAt: DateTime(2026, 10, 1),
          updatedAt: DateTime(2026, 10, 10),
        ),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _validateName(String name) {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 100) {
      throw ArgumentError('Tên danh sách phải có từ 1 đến 100 ký tự.');
    }
    return clean;
  }

  List<_ListRecord> _recordsFor(String boardId) =>
      _store.putIfAbsent(boardId, () => []);

  List<TaskListModel> _getActiveLists(String boardId) {
    final active =
        _recordsFor(
            boardId,
          ).where((r) => !r.model.isArchived).map((r) => r.model).toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    return active;
  }

  List<TaskListModel> _getArchivedLists(String boardId) {
    final archived =
        _recordsFor(
            boardId,
          ).where((r) => r.model.isArchived).map((r) => r.model).toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    return archived;
  }

  /// Phát danh sách active (archivedAt == null), sắp xếp tăng dần theo position,
  /// đến StreamController của boardId tương ứng.
  void _emit(String boardId) {
    final controller = _controllers[boardId];
    if (controller != null && !controller.isClosed) {
      controller.add(_getActiveLists(boardId));
    }
    final archivedController = _archivedControllers[boardId];
    if (archivedController != null && !archivedController.isClosed) {
      archivedController.add(_getArchivedLists(boardId));
    }
  }

  _ListRecord _findRecord(String boardId, String listId) {
    final records = _recordsFor(boardId);
    final idx = records.indexWhere((r) => r.model.id == listId);
    if (idx == -1) {
      throw StateError(
        'Không tìm thấy danh sách "$listId" trong board "$boardId".',
      );
    }
    return records[idx];
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  @override
  Stream<List<TaskListModel>> getListsByBoardId(String boardId) async* {
    final controller = _controllers.putIfAbsent(
      boardId,
      () => StreamController<List<TaskListModel>>.broadcast(),
    );
    yield _getActiveLists(boardId);
    yield* controller.stream;
  }

  @override
  Stream<List<TaskListModel>> getArchivedListsByBoardId(String boardId) async* {
    final controller = _archivedControllers.putIfAbsent(
      boardId,
      () => StreamController<List<TaskListModel>>.broadcast(),
    );
    yield _getArchivedLists(boardId);
    yield* controller.stream;
  }

  @override
  Stream<List<TaskListModel>> watchLists(String boardId) =>
      getListsByBoardId(boardId);

  // ---------------------------------------------------------------------------
  // Write — Create
  // ---------------------------------------------------------------------------

  @override
  Future<String> createList({
    required String boardId,
    required String name,
    double? position,
  }) async {
    final cleanName = _validateName(name);
    final records = _recordsFor(boardId);

    double targetPosition = position ?? 0.0;
    if (position == null) {
      final maxPosition = records.isEmpty
          ? 0.0
          : records
                .map((r) => r.model.position)
                .reduce((a, b) => a > b ? a : b);
      targetPosition = maxPosition + 1000.0;
    }

    final id =
        'list_${DateTime.now().millisecondsSinceEpoch}_${records.length}';
    final now = DateTime.now();

    final newModel = TaskListModel(
      id: id,
      name: cleanName,
      position: targetPosition,
      archivedAt: null,
      createdAt: now,
      updatedAt: now,
    );

    records.add(_ListRecord(model: newModel));
    _emit(boardId);
    return id;
  }

  // ---------------------------------------------------------------------------
  // Write — Update
  // ---------------------------------------------------------------------------

  @override
  Future<void> updateList({
    required String boardId,
    required String listId,
    String? name,
    double? position,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
  }) async {
    final record = _findRecord(boardId, listId);
    final old = record.model;

    DateTime? nextArchivedAt = old.archivedAt;
    if (clearArchivedAt) {
      nextArchivedAt = null;
    } else if (archivedAt != null) {
      nextArchivedAt = archivedAt;
    }

    record.model = TaskListModel(
      id: old.id,
      name: name != null ? _validateName(name) : old.name,
      position: position ?? old.position,
      archivedAt: nextArchivedAt,
      createdAt: old.createdAt,
      updatedAt: DateTime.now(),
    );

    _emit(boardId);
  }

  @override
  Future<void> renameList({
    required String boardId,
    required String listId,
    required String newName,
  }) async {
    await updateList(boardId: boardId, listId: listId, name: newName);
  }

  // ---------------------------------------------------------------------------
  // Write — Delete / Archive / Restore
  // ---------------------------------------------------------------------------

  /// Xóa List (soft-delete theo schema § 4.6): đánh dấu `archivedAt`.
  @override
  Future<void> deleteList({required String boardId, required String listId}) =>
      archiveList(boardId: boardId, listId: listId);

  @override
  Future<void> archiveList({
    required String boardId,
    required String listId,
  }) async {
    final record = _findRecord(boardId, listId);
    final now = DateTime.now();

    record.model = TaskListModel(
      id: record.model.id,
      name: record.model.name,
      position: record.model.position,
      archivedAt: now,
      createdAt: record.model.createdAt,
      updatedAt: now,
    );
    _emit(boardId);
  }

  @override
  Future<void> unarchiveList({
    required String boardId,
    required String listId,
  }) async {
    final record = _findRecord(boardId, listId);

    record.model = TaskListModel(
      id: record.model.id,
      name: record.model.name,
      position: record.model.position,
      archivedAt: null,
      createdAt: record.model.createdAt,
      updatedAt: DateTime.now(),
    );
    _emit(boardId);
  }

  // ---------------------------------------------------------------------------
  // Write — Reorder
  // ---------------------------------------------------------------------------

  @override
  Future<void> reorderLists({
    required String boardId,
    required List<String> orderedListIds,
  }) async {
    if (orderedListIds.isEmpty) return;

    final records = _recordsFor(boardId);
    for (var i = 0; i < orderedListIds.length; i++) {
      final idx = records.indexWhere((r) => r.model.id == orderedListIds[i]);
      if (idx == -1) continue;

      final old = records[idx].model;
      records[idx].model = TaskListModel(
        id: old.id,
        name: old.name,
        position: (i + 1) * 1000.0,
        archivedAt: old.archivedAt,
        createdAt: old.createdAt,
        updatedAt: DateTime.now(),
      );
    }
    _emit(boardId);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
    for (final c in _archivedControllers.values) {
      c.close();
    }
    _controllers.clear();
    _archivedControllers.clear();
  }
}
