import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_todo/features/boards/domain/board_models.dart';
import 'package:smart_todo/features/lists/data/fake_list_repository.dart';
import 'package:smart_todo/features/lists/data/firestore_list_repository.dart';
import 'package:smart_todo/features/lists/data/list_model.dart';
import 'package:smart_todo/features/lists/data/list_repository.dart';

/// Cung cấp UID của người dùng hiện tại từ phiên đăng nhập Firebase.
/// Trả về `null` nếu ở chế độ xem trước (preview) hoặc chưa đăng nhập.
final currentUserIdProvider = StreamProvider<String?>((ref) {
  if (Firebase.apps.isEmpty) {
    return Stream.value(null);
  }
  return FirebaseAuth.instance.authStateChanges().map((user) => user?.uid);
});

/// Provider cung cấp [ListRepository].
///
/// Tự động chuyển đổi giữa:
/// - [FirestoreListRepository]: khi Firebase đã cấu hình và người dùng đã đăng nhập.
/// - [FakeListRepository]: khi ở chế độ xem trước (offline / preview) hoặc testing.
final listRepositoryProvider = Provider<ListRepository>((ref) {
  final userId = ref.watch(currentUserIdProvider).asData?.value;
  if (Firebase.apps.isNotEmpty && userId != null) {
    return FirestoreListRepository();
  }
  final repo = FakeListRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Luồng danh sách active (`archivedAt == null`) cho một board cụ thể,
/// sắp xếp theo thứ tự `position`.
///
/// Tự động kết nối real-time với Firestore subcollection qua [ListRepository.getListsByBoardId].
final boardListsStreamProvider =
    StreamProvider.family<List<TaskListModel>, String>((ref, boardId) {
  final repo = ref.watch(listRepositoryProvider);
  return repo.getListsByBoardId(boardId);
});

/// Trạng thái thao tác danh sách (loading, lỗi).
class ListOperationState {
  const ListOperationState({
    this.isLoading = false,
    this.errorMessage,
  });

  final bool isLoading;
  final String? errorMessage;

  bool get hasError => errorMessage != null;

  ListOperationState copyWith({
    bool? isLoading,
    String? errorMessage,
  }) {
    return ListOperationState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

/// Controller quản lý các thao tác ghi (create, update, delete, reorder) cho List.
class BoardListsController extends Notifier<ListOperationState> {
  @override
  ListOperationState build() => const ListOperationState();

  ListRepository get _repository => ref.read(listRepositoryProvider);

  /// Xóa thông báo lỗi hiện tại.
  void clearError() {
    if (state.errorMessage != null) {
      state = state.copyWith(errorMessage: null);
    }
  }

  /// Tạo List mới trong board.
  Future<bool> createList({
    required String boardId,
    required String name,
    double? position,
  }) async {
    state = const ListOperationState(isLoading: true);
    try {
      await _repository.createList(
        boardId: boardId,
        name: name,
        position: position,
      );
      state = const ListOperationState(isLoading: false);
      return true;
    } catch (e) {
      state = ListOperationState(
        isLoading: false,
        errorMessage: _formatError(e),
      );
      return false;
    }
  }

  /// Đổi tên List.
  Future<bool> renameList({
    required String boardId,
    required String listId,
    required String newName,
  }) async {
    state = const ListOperationState(isLoading: true);
    try {
      await _repository.renameList(
        boardId: boardId,
        listId: listId,
        newName: newName,
      );
      state = const ListOperationState(isLoading: false);
      return true;
    } catch (e) {
      state = ListOperationState(
        isLoading: false,
        errorMessage: _formatError(e),
      );
      return false;
    }
  }

  /// Lưu trữ một List (soft-delete).
  Future<bool> archiveList({
    required String boardId,
    required String listId,
  }) async {
    state = const ListOperationState(isLoading: true);
    try {
      await _repository.archiveList(boardId: boardId, listId: listId);
      state = const ListOperationState(isLoading: false);
      return true;
    } catch (e) {
      state = ListOperationState(
        isLoading: false,
        errorMessage: _formatError(e),
      );
      return false;
    }
  }

  /// Xóa List (soft-delete theo schema § 4.6 và Firestore security rules).
  ///
  /// Không tự ý xóa Card thuộc List ở tầng này.
  Future<bool> deleteList({
    required String boardId,
    required String listId,
  }) =>
      archiveList(boardId: boardId, listId: listId);

  /// Khôi phục một List đã lưu trữ.
  Future<bool> unarchiveList({
    required String boardId,
    required String listId,
  }) async {
    state = const ListOperationState(isLoading: true);
    try {
      await _repository.unarchiveList(boardId: boardId, listId: listId);
      state = const ListOperationState(isLoading: false);
      return true;
    } catch (e) {
      state = ListOperationState(
        isLoading: false,
        errorMessage: _formatError(e),
      );
      return false;
    }
  }

  /// Sắp xếp lại danh sách các List theo thứ tự [orderedListIds].
  Future<bool> reorderLists({
    required String boardId,
    required List<String> orderedListIds,
  }) async {
    try {
      await _repository.reorderLists(
        boardId: boardId,
        orderedListIds: orderedListIds,
      );
      return true;
    } catch (e) {
      state = ListOperationState(
        isLoading: false,
        errorMessage: _formatError(e),
      );
      return false;
    }
  }

  /// Thêm thẻ tạm thời trong chế độ preview (phục vụ prototype/dev UI).
  Future<void> addPrototypeCard({
    required String boardId,
    required String listId,
    required String title,
  }) async {
    if (_repository is FakeListRepository) {
      final repo = _repository as FakeListRepository;
      repo.addCardToList(
        boardId: boardId,
        listId: listId,
        card: BoardCard(title: title),
      );
    }
  }

  String _formatError(Object error) {
    if (error is ArgumentError) {
      return error.message?.toString() ?? error.toString();
    }
    return error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('StateError: ', '');
  }
}

/// Provider cho [BoardListsController].
final boardListsControllerProvider =
    NotifierProvider<BoardListsController, ListOperationState>(
  BoardListsController.new,
);
