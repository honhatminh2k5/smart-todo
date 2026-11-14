import 'dart:async';

import '../../boards/data/boards_repository.dart';
import '../../cards/data/card_model.dart';
import '../domain/collaboration_rules.dart';
import 'collaboration_models.dart';
import 'collaboration_repository.dart';

/// Triển khai [CollaborationRepository] hoàn toàn trong bộ nhớ.
///
/// Phục vụ preview khi chưa cấu hình Firebase và test không cần Firestore.
/// Dữ liệu mẫu dùng cùng board `thesis_board` với `FakeCardRepository`.
/// Quyền được kiểm tra giống `firestore.rules` để test giao diện sát thực tế.
class FakeCollaborationRepository implements CollaborationRepository {
  FakeCollaborationRepository({
    bool seed = true,
    this.currentUserId = 'preview_user',
    this.currentUserEmail = 'preview@example.com',
    this.currentUserName = 'Người dùng xem trước',
  }) {
    if (seed) _seed();
  }

  @override
  final String? currentUserId;
  final String currentUserEmail;
  final String currentUserName;

  /// Khi khác `null`, mọi thao tác ghi ném lỗi này (giả lập mất kết nối).
  Object? writeError;

  final Map<String, BoardSummary> _boards = {};
  final Map<String, Map<String, BoardMember>> _members = {};

  // boardId -> normalizedEmail -> lời mời (mọi trạng thái)
  final Map<String, Map<String, BoardInvitation>> _invitations = {};

  // 'boardId/cardId' -> commentId -> bình luận
  final Map<String, Map<String, CardComment>> _comments = {};

  /// uid đã bị gỡ khỏi board qua [removeMember] / [leaveBoard], để test kiểm
  /// tra việc dọn người được giao (do `FirestoreCollaborationRepository` làm).
  final List<({String boardId, String uid})> detachedMembers = [];

  final StreamController<void> _changes = StreamController<void>.broadcast();
  int _nextId = 0;
  DateTime _clock = DateTime(2026, 11, 1, 8);

  // ---------------------------------------------------------------------------
  // Seed data và hàm cho test
  // ---------------------------------------------------------------------------

  void _seed() {
    const boardId = 'thesis_board';
    putBoard(
      id: boardId,
      name: 'Khóa luận tốt nghiệp',
      ownerId: 'preview_user',
      members: const [
        BoardMember(
          uid: 'preview_user',
          displayName: 'Người dùng xem trước',
          email: 'preview@example.com',
          role: 'owner',
        ),
        BoardMember(
          uid: 'member_an',
          displayName: 'Nguyễn An',
          email: 'an@example.com',
          role: 'member',
        ),
      ],
    );
    final created = DateTime(2026, 10, 2, 9, 30);
    _comments['$boardId/card_read'] = {
      'comment_1': CardComment(
        id: 'comment_1',
        authorId: 'member_an',
        authorName: 'Nguyễn An',
        body: 'Mình đã tìm được 3 bài báo liên quan.',
        createdAt: created,
        updatedAt: created,
      ),
      'comment_2': CardComment(
        id: 'comment_2',
        authorId: 'preview_user',
        authorName: 'Người dùng xem trước',
        body: 'Cảm ơn, mình sẽ đọc trong tuần này.',
        createdAt: created.add(const Duration(hours: 2)),
        updatedAt: created.add(const Duration(hours: 2)),
      ),
    };
  }

  /// Tạo (hoặc thay) một board cùng danh sách thành viên.
  void putBoard({
    required String id,
    required String name,
    required String ownerId,
    required List<BoardMember> members,
    DateTime? archivedAt,
  }) {
    _members[id] = {for (final member in members) member.uid: member};
    _boards[id] = BoardSummary(
      id: id,
      name: name,
      description: '',
      ownerId: ownerId,
      memberIds: [for (final member in members) member.uid],
      updatedAt: _clock,
      archivedAt: archivedAt,
    );
    _emit();
  }

  /// Thêm sẵn một lời mời (mặc định đang chờ).
  void putInvitation(BoardInvitation invitation) {
    _invitations.putIfAbsent(
      invitation.boardId,
      () => {},
    )[invitation.normalizedEmail] = invitation;
    _emit();
  }

  /// Lời mời của board theo email chuẩn hóa (mọi trạng thái).
  BoardInvitation? invitationOf(String boardId, String normalizedEmail) =>
      _invitations[boardId]?[normalizedEmail];

  /// Giả lập Owner hủy lời mời từ một thiết bị khác.
  void deleteInvitation(String boardId, String normalizedEmail) {
    _invitations[boardId]?.remove(normalizedEmail);
    _emit();
  }

  /// Thông tin board hiện tại (cho test).
  BoardSummary? boardOf(String boardId) => _boards[boardId];

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  DateTime _now() => _clock = _clock.add(const Duration(minutes: 1));

  void _checkWritable() {
    final error = writeError;
    if (error != null) throw error;
  }

  String _requireUser() {
    final uid = currentUserId;
    if (uid == null) {
      throw StateError('Bạn cần đăng nhập trước khi thực hiện thao tác này.');
    }
    return uid;
  }

  BoardSummary _requireBoard(String boardId) {
    final board = _boards[boardId];
    if (board == null) {
      throw const CollaborationException('Board không còn tồn tại.');
    }
    return board;
  }

  void _setMemberIds(BoardSummary board, List<String> memberIds) {
    _boards[board.id] = BoardSummary(
      id: board.id,
      name: board.name,
      description: board.description,
      ownerId: board.ownerId,
      memberIds: memberIds,
      updatedAt: board.updatedAt,
      archivedAt: board.archivedAt,
    );
  }

  Map<String, CardComment> _cardComments(String boardId, String cardId) =>
      _comments.putIfAbsent('$boardId/$cardId', () => {});

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  @override
  Stream<BoardSummary?> watchBoard(String boardId) =>
      _watch(() => _boards[boardId]);

  @override
  Stream<List<BoardMember>> watchMembers(String boardId) => _watch(
    () =>
        (_members[boardId]?.values.toList() ?? <BoardMember>[])
          ..sort(compareMembers),
  );

  @override
  Stream<List<BoardInvitation>> watchPendingInvitations(String boardId) =>
      _watch(
        () =>
            (_invitations[boardId]?.values ?? const <BoardInvitation>[])
                .where((invitation) => invitation.isPending)
                .toList()
              ..sort(BoardInvitation.newestFirst),
      );

  @override
  Stream<List<BoardInvitation>> watchMyInvitations() {
    final email = normalizeEmail(currentUserEmail);
    return _watch(
      () =>
          [for (final invitations in _invitations.values) ?invitations[email]]
              .where((invitation) => invitation.isPending)
              .toList()
            ..sort(BoardInvitation.newestFirst),
    );
  }

  @override
  Stream<List<CardComment>> watchComments({
    required String boardId,
    required String cardId,
  }) => _watch(
    () =>
        _cardComments(boardId, cardId).values.toList()
          ..sort(CardComment.oldestFirst),
  );

  // ---------------------------------------------------------------------------
  // Lời mời
  // ---------------------------------------------------------------------------

  @override
  Future<void> inviteMember({
    required String boardId,
    required String email,
  }) async {
    final uid = _requireUser();
    final formatError = validateInviteEmail(email);
    if (formatError != null) throw ArgumentError(formatError);
    _checkWritable();
    final cleanEmail = email.trim();
    final normalized = normalizeEmail(cleanEmail);
    final board = _requireBoard(boardId);
    if (board.ownerId != uid) {
      throw const CollaborationException('Chỉ Owner mới được mời thành viên.');
    }
    final isMember = (_members[boardId]?.values ?? const <BoardMember>[]).any(
      (member) => normalizeEmail(member.email) == normalized,
    );
    if (isMember) {
      throw CollaborationException('$cleanEmail đã là thành viên của board.');
    }
    if (invitationOf(boardId, normalized)?.isPending ?? false) {
      throw CollaborationException(
        'Đã có lời mời đang chờ gửi tới $cleanEmail.',
      );
    }
    final now = _now();
    putInvitation(
      BoardInvitation(
        boardId: boardId,
        email: cleanEmail,
        normalizedEmail: normalized,
        invitedBy: uid,
        inviterName: displayNameFor(
          displayName: currentUserName,
          email: currentUserEmail,
        ),
        boardName: board.name,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  @override
  Future<void> cancelInvitation({
    required String boardId,
    required String normalizedEmail,
  }) async {
    _requireUser();
    _checkWritable();
    final invitation = invitationOf(boardId, normalizedEmail);
    if (invitation == null) return;
    if (!invitation.isPending) {
      throw CollaborationException(
        invitation.status == InvitationStatus.accepted
            ? 'Người này đã chấp nhận lời mời nên không hủy được.'
            : 'Lời mời đã được trả lời nên không hủy được.',
      );
    }
    deleteInvitation(boardId, normalizedEmail);
  }

  @override
  Future<void> acceptInvitation(BoardInvitation invitation) async {
    final uid = _requireUser();
    if (normalizeEmail(currentUserEmail) != invitation.normalizedEmail) {
      throw const CollaborationException(
        'Lời mời này không gửi tới email của bạn.',
      );
    }
    _checkWritable();
    final current = invitationOf(
      invitation.boardId,
      invitation.normalizedEmail,
    );
    final board = _boards[invitation.boardId];
    if (current == null || !current.isPending || board == null) {
      throw const CollaborationException(kInvitationNoLongerValid);
    }
    final now = _now();
    _invitations[invitation.boardId]![invitation.normalizedEmail] = current
        .copyWith(status: InvitationStatus.accepted, updatedAt: now);
    _members.putIfAbsent(board.id, () => {})[uid] = BoardMember(
      uid: uid,
      displayName: displayNameFor(
        displayName: currentUserName,
        email: currentUserEmail,
      ),
      email: currentUserEmail,
      role: 'member',
    );
    _setMemberIds(board, {...board.memberIds, uid}.toList());
    _emit();
  }

  @override
  Future<void> declineInvitation(BoardInvitation invitation) async {
    _requireUser();
    _checkWritable();
    final current = invitationOf(
      invitation.boardId,
      invitation.normalizedEmail,
    );
    if (current == null || !current.isPending) {
      throw const CollaborationException(kInvitationNoLongerValid);
    }
    _invitations[invitation.boardId]![invitation.normalizedEmail] = current
        .copyWith(status: InvitationStatus.declined, updatedAt: _now());
    _emit();
  }

  // ---------------------------------------------------------------------------
  // Thành viên
  // ---------------------------------------------------------------------------

  @override
  Future<void> removeMember({
    required String boardId,
    required String memberUid,
  }) async {
    final uid = _requireUser();
    _checkWritable();
    final board = _requireBoard(boardId);
    if (board.ownerId != uid) {
      throw const CollaborationException('Chỉ Owner mới được xóa thành viên.');
    }
    if (memberUid == board.ownerId) {
      throw const CollaborationException('Không thể xóa Owner khỏi board.');
    }
    if (!board.memberIds.contains(memberUid)) {
      throw const CollaborationException(
        'Người này không còn là thành viên của board.',
      );
    }
    _detach(board, memberUid);
  }

  @override
  Future<void> leaveBoard(String boardId) async {
    final uid = _requireUser();
    _checkWritable();
    final board = _requireBoard(boardId);
    if (board.ownerId == uid) {
      throw const CollaborationException('Owner không thể rời board.');
    }
    if (!board.memberIds.contains(uid)) {
      throw const CollaborationException(
        'Bạn không còn là thành viên của board.',
      );
    }
    _detach(board, uid);
  }

  void _detach(BoardSummary board, String memberUid) {
    _members[board.id]?.remove(memberUid);
    _setMemberIds(
      board,
      board.memberIds.where((id) => id != memberUid).toList(),
    );
    detachedMembers.add((boardId: board.id, uid: memberUid));
    _emit();
  }

  // ---------------------------------------------------------------------------
  // Bình luận
  // ---------------------------------------------------------------------------

  @override
  Future<void> addComment({
    required String boardId,
    required String cardId,
    required String body,
  }) async {
    final cleanBody = normalizeCommentBody(body);
    final uid = _requireUser();
    _checkWritable();
    final now = _now();
    final id = 'comment_new_${_nextId++}';
    _cardComments(boardId, cardId)[id] = CardComment(
      id: id,
      authorId: uid,
      authorName: displayNameFor(
        displayName: currentUserName,
        email: currentUserEmail,
      ),
      body: cleanBody,
      createdAt: now,
      updatedAt: now,
    );
    _emit();
  }

  @override
  Future<void> editComment({
    required String boardId,
    required String cardId,
    required String commentId,
    required String body,
  }) async {
    final cleanBody = normalizeCommentBody(body);
    final uid = _requireUser();
    _checkWritable();
    final comments = _cardComments(boardId, cardId);
    final comment = comments[commentId];
    if (comment == null) {
      throw const CollaborationException('Bình luận không còn tồn tại.');
    }
    if (comment.authorId != uid) {
      throw const CollaborationException(
        'Bạn chỉ sửa được bình luận của mình.',
      );
    }
    comments[commentId] = comment.copyWith(body: cleanBody, updatedAt: _now());
    _emit();
  }

  @override
  Future<void> deleteComment({
    required String boardId,
    required String cardId,
    required String commentId,
  }) async {
    final uid = _requireUser();
    _checkWritable();
    final comments = _cardComments(boardId, cardId);
    final comment = comments[commentId];
    if (comment == null) {
      throw const CollaborationException('Bình luận không còn tồn tại.');
    }
    final isOwner = _boards[boardId]?.ownerId == uid;
    if (comment.authorId != uid && !isOwner) {
      throw const CollaborationException(
        'Chỉ tác giả hoặc Owner được xóa bình luận.',
      );
    }
    comments.remove(commentId);
    _emit();
  }

  /// Số bình luận hiện có của một card (cho test).
  int commentCountOf(String boardId, String cardId) =>
      _cardComments(boardId, cardId).length;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void dispose() {
    _changes.close();
  }
}
