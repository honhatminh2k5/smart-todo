import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../collaboration/presentation/screens/board_members_screen.dart';
import '../../lists/presentation/widgets/board_lists_section.dart';
import '../../lists/presentation/widgets/archived_lists_sheet.dart';
import '../../search/presentation/screens/board_search_screen.dart';

class BoardDetailScreen extends StatelessWidget {
  const BoardDetailScreen({required this.boardId, super.key});

  final String boardId;

  void _openMembers(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BoardMembersScreen(boardId: boardId),
      ),
    );
  }

  /// Bị Owner xóa khỏi board hoặc đã rời board (UC06 2c): Rules từ chối đọc.
  Widget _accessLost(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Board')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 14),
              const Text(
                'Bạn không còn là thành viên của board này nên không thể xem '
                'nội dung board.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Về danh sách board'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boardStream = FirebaseFirestore.instance
        .collection('boards')
        .doc(boardId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: boardStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: Text('Board')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final error = snapshot.error;
        if (error is FirebaseException && error.code == 'permission-denied') {
          return _accessLost(context);
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Board')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Không tải được board. Hãy kiểm tra quyền truy cập và kết nối Firestore.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text('Board')),
            body: const Center(
              child: Text(
                'Board không tồn tại hoặc bạn không còn quyền truy cập.',
              ),
            ),
          );
        }

        final data = snapshot.data!.data()!;
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final ownerId = data['ownerId'] as String? ?? '';
        final isOwner = currentUid != null && currentUid == ownerId;
        final name = data['name'] as String? ?? '(Chưa có tên)';
        final description = data['description'] as String? ?? '';
        final memberIds = (data['memberIds'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false);
        if (currentUid != null && !memberIds.contains(currentUid)) {
          return _accessLost(context);
        }
        final archivedAt = data['archivedAt'];
        final theme = Theme.of(context);

        return Scaffold(
          appBar: AppBar(
            leading: const BackButton(),
            titleSpacing: 0,
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Tìm kiếm',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          BoardSearchScreen(boardId: boardId, boardTitle: name),
                    ),
                  );
                },
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: 'Thành viên',
                onPressed: () => _openMembers(context),
                icon: const Icon(Icons.group_add_outlined),
              ),
              PopupMenuButton<String>(
                tooltip: 'Tùy chọn board',
                onSelected: (value) {
                  if (value == 'archived_lists') {
                    ArchivedListsSheet.show(context, boardId: boardId);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem<String>(
                    value: 'archived_lists',
                    child: Text('Danh sách đã lưu trữ'),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                if (description.isNotEmpty) ...[
                  Text(
                    description,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      avatar: Icon(
                        isOwner
                            ? Icons.verified_user_outlined
                            : Icons.person_outline,
                        size: 18,
                      ),
                      label: Text(isOwner ? 'Owner' : 'Member'),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.people_outline, size: 18),
                      label: Text('${memberIds.length} thành viên'),
                      onPressed: () => _openMembers(context),
                    ),
                    if (archivedAt != null)
                      const Chip(
                        avatar: Icon(Icons.archive_outlined, size: 18),
                        label: Text('Đã lưu trữ'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                BoardListsSection(boardId: boardId),
              ],
            ),
          ),
        );
      },
    );
  }
}
