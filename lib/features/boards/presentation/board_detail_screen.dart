import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../lists/presentation/widgets/board_lists_section.dart';

/// Màn hình chi tiết board kết nối UC03 (Boards) với UC04 (Lists).
class BoardDetailScreen extends StatelessWidget {
  const BoardDetailScreen({required this.boardId, super.key});

  final String boardId;

  @override
  Widget build(BuildContext context) {
    final boardStream = FirebaseFirestore.instance
        .collection('boards')
        .doc(boardId)
        .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết board')),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: boardStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Không tải được board. Hãy kiểm tra quyền truy cập và kết nối Firestore.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                child: Text(
                  'Board không tồn tại hoặc bạn không còn quyền truy cập.',
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
            final archivedAt = data['archivedAt'];

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      child: Icon(Icons.dashboard_outlined, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
                const SizedBox(height: 16),
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
                    Chip(
                      avatar: const Icon(Icons.people_outline, size: 18),
                      label: Text('${memberIds.length} thành viên'),
                    ),
                    if (archivedAt != null)
                      const Chip(
                        avatar: Icon(Icons.archive_outlined, size: 18),
                        label: Text('Đã lưu trữ'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                // Khu vực hiển thị danh sách công việc (UC04)
                BoardListsSection(boardId: boardId),
              ],
            );
          },
        ),
      ),
    );
  }
}
