import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// A lightweight detail screen so UC03 can navigate to the selected board.
/// UC04 (Lists) and UC05 (Cards) can later replace the placeholder section below.
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
                const SizedBox(height: 28),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Khu vực công việc',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Điều hướng từ UC03 đã hoạt động. Phần danh sách (List) và thẻ công việc (Card) '
                          'sẽ được kết nối với các chức năng UC04 và UC05 của dự án.',
                        ),
                        const SizedBox(height: 12),
                        SelectableText(
                          'Board ID: $boardId',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
