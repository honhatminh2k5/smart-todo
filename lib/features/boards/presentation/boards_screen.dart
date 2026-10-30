import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../auth/data/auth_repository.dart';
import '../data/boards_repository.dart';
import 'board_detail_screen.dart';

class BoardsScreen extends StatefulWidget {
  const BoardsScreen({required this.user, required this.auth, super.key});

  final User user;
  final AuthRepository auth;

  @override
  State<BoardsScreen> createState() => _BoardsScreenState();
}

class _BoardsScreenState extends State<BoardsScreen> {
  late final BoardsRepository _repository;
  late Stream<List<BoardSummary>> _boardsStream;

  bool _creatingBoard = false;
  bool _signingOut = false;

  final Set<String> _busyBoardIds = <String>{};

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _repository = BoardsRepository();
    _boardsStream = _repository.watchMyBoards(widget.user.uid);
  }

  // Tải lại danh sách board.
  Future<void> _reloadBoards() async {
    setState(() {
      _boardsStream = _repository.watchMyBoards(widget.user.uid);
    });
  }

  // Hiển thị biểu mẫu tạo hoặc sửa board.
  Future<void> _showBoardForm({BoardSummary? board}) async {
    _nameController.text = board?.name ?? '';
    _descriptionController.text = board?.description ?? '';

    String? dialogError;

    final formData = await showDialog<({String name, String description})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(board == null ? 'Tạo board mới' : 'Sửa thông tin board'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  autofocus: true,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Tên board *',
                    hintText: 'Ví dụ: Đồ án môn học',
                  ),
                  onChanged: (_) {
                    if (dialogError != null) {
                      setDialogState(() {
                        dialogError = null;
                      });
                    }
                  },
                ),
                TextField(
                  controller: _descriptionController,
                  maxLength: 500,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả (không bắt buộc)',
                  ),
                ),
                if (dialogError != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      dialogError!,
                      style: TextStyle(
                        color: Theme.of(dialogContext).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final name = _nameController.text.trim();
                final description = _descriptionController.text.trim();

                if (name.isEmpty) {
                  setDialogState(() {
                    dialogError = 'Bạn cần nhập tên board.';
                  });
                  return;
                }

                if (name.length > 100) {
                  setDialogState(() {
                    dialogError = 'Tên board tối đa 100 ký tự.';
                  });
                  return;
                }

                if (description.length > 500) {
                  setDialogState(() {
                    dialogError = 'Mô tả tối đa 500 ký tự.';
                  });
                  return;
                }

                Navigator.of(
                  dialogContext,
                ).pop((name: name, description: description));
              },
              child: Text(board == null ? 'Tạo board' : 'Lưu thay đổi'),
            ),
          ],
        ),
      ),
    );

    // Không tiếp tục nếu người dùng nhấn Hủy.
    if (formData == null || !mounted) {
      return;
    }

    if (board == null) {
      await _createBoard(formData.name, formData.description);
    } else {
      await _runBoardAction(
        board,
        () => _repository.updateBoard(
          boardId: board.id,
          name: formData.name,
          description: formData.description,
        ),
        successMessage: 'Đã cập nhật thông tin board.',
      );
    }
  }

  // Tạo board mới.
  Future<void> _createBoard(String name, String description) async {
    if (_creatingBoard) {
      return;
    }

    setState(() {
      _creatingBoard = true;
    });

    try {
      final boardId = await _repository.createBoard(
        name: name,
        description: description,
      );

      if (!mounted) {
        return;
      }

      _showMessage('Đã tạo board thành công.');

      // Mở màn hình chi tiết của board vừa tạo.
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => BoardDetailScreen(boardId: boardId),
        ),
      );
    } on FirebaseException catch (error) {
      if (mounted) {
        _showError(_firebaseErrorMessage(error));
      }
    } catch (error) {
      if (mounted) {
        _showError(_friendlyErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _creatingBoard = false;
        });
      }
    }
  }

  // Hiển thị hộp thoại xác nhận lưu trữ.
  Future<void> _confirmArchive(BoardSummary board) async {
    final shouldArchive = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lưu trữ board?'),
        content: Text(
          'Board "${board.name}" sẽ được ẩn khỏi danh sách chính. '
          'Bạn có thể khôi phục board sau này.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Lưu trữ'),
          ),
        ],
      ),
    );

    if (shouldArchive != true || !mounted) {
      return;
    }

    await _runBoardAction(
      board,
      () => _repository.archiveBoard(board.id),
      successMessage: 'Đã lưu trữ board.',
    );
  }

  // Xử lý các lựa chọn trong menu board.
  Future<void> _handleBoardMenu(
    BoardSummary board,
    _BoardMenuAction action,
  ) async {
    switch (action) {
      case _BoardMenuAction.edit:
        await _showBoardForm(board: board);
        break;

      case _BoardMenuAction.archive:
        await _confirmArchive(board);
        break;
    }
  }

  // Thực hiện thao tác sửa hoặc lưu trữ board.
  Future<void> _runBoardAction(
    BoardSummary board,
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    if (_busyBoardIds.contains(board.id)) {
      return;
    }

    setState(() {
      _busyBoardIds.add(board.id);
    });

    try {
      await action();

      if (mounted) {
        _showMessage(successMessage);
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        _showError(_firebaseErrorMessage(error));
      }
    } catch (error) {
      if (mounted) {
        _showError(_friendlyErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyBoardIds.remove(board.id);
        });
      }
    }
  }

  // Mở màn hình board đã lưu trữ.
  Future<void> _openArchivedBoards() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            ArchivedBoardsScreen(user: widget.user, repository: _repository),
      ),
    );
  }

  // Mở màn hình chi tiết board.
  Future<void> _openBoard(BoardSummary board) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BoardDetailScreen(boardId: board.id),
      ),
    );
  }

  // Đăng xuất.
  Future<void> _signOut() async {
    if (_signingOut) {
      return;
    }

    setState(() {
      _signingOut = true;
    });

    try {
      await widget.auth.signOut();
    } on AuthFailure catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } finally {
      if (mounted) {
        setState(() {
          _signingOut = false;
        });
      }
    }
  }

  // Hiển thị thông báo thành công.
  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Hiển thị thông báo lỗi.
  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // Chuyển lỗi Firebase thành thông báo dễ hiểu.
  String _firebaseErrorMessage(FirebaseException error) {
    if (error.code == 'permission-denied') {
      return 'Bạn không có quyền thực hiện thao tác này.';
    }

    if (error.code == 'unavailable' || error.code == 'network-request-failed') {
      return 'Không kết nối được Firestore. '
          'Hãy kiểm tra mạng hoặc Emulator rồi thử lại.';
    }

    return 'Firestore báo lỗi: ${error.message ?? error.code}';
  }

  // Chuyển lỗi thông thường thành thông báo.
  String _friendlyErrorMessage(Object error) {
    if (error is ArgumentError || error is StateError) {
      return error.toString().replaceFirst('Invalid argument(s): ', '');
    }

    return 'Không thực hiện được thao tác. Chi tiết: $error';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.user.displayName?.trim().isNotEmpty == true
        ? widget.user.displayName!.trim()
        : widget.user.email ?? 'bạn';

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Color(0xFF3157D5)),
            SizedBox(width: 8),
            Text('Smart Todo · Board'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Board đã lưu trữ',
            onPressed: _openArchivedBoards,
            icon: const Icon(Icons.archive_outlined),
          ),
          if (_signingOut)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'Đăng xuất',
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: CircleAvatar(
              child: Text(
                displayName.isEmpty ? '?' : displayName[0].toUpperCase(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<BoardSummary>>(
          stream: _boardsStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _MessageState(
                icon: Icons.cloud_off_outlined,
                title: 'Không đọc được board từ Firestore',
                message:
                    'Kiểm tra Emulator, tài khoản đăng nhập '
                    'và Security Rules.',
                actionLabel: 'Thử tải lại',
                onAction: _reloadBoards,
              );
            }

            final allBoards = snapshot.data ?? const <BoardSummary>[];

            final activeBoards = allBoards
                .where((board) => !board.isArchived)
                .toList(growable: false);

            if (allBoards.isEmpty) {
              return _MessageState(
                icon: Icons.dashboard_outlined,
                title: 'Chưa có board nào',
                message:
                    'Hãy tạo board đầu tiên. '
                    'Dữ liệu sẽ được lưu vào Firestore.',
                actionLabel: 'Tạo board đầu tiên',
                onAction: _creatingBoard ? null : () => _showBoardForm(),
                loading: _creatingBoard,
              );
            }

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Xin chào $displayName 👋',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Board của tôi',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Danh sách được đồng bộ trực tiếp '
                  'từ Cloud Firestore.',
                ),
                const SizedBox(height: 18),
                if (activeBoards.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: _InlineEmptyState(
                      icon: Icons.dashboard_outlined,
                      message:
                          'Không có board đang hoạt động. '
                          'Bạn có thể tạo board mới hoặc mở '
                          'mục Board đã lưu trữ.',
                    ),
                  )
                else
                  for (final board in activeBoards) _buildBoardTile(board),
                const SizedBox(height: 80),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creatingBoard ? null : () => _showBoardForm(),
        icon: _creatingBoard
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(_creatingBoard ? 'Đang tạo...' : 'Tạo board'),
      ),
    );
  }

  // Tạo giao diện cho từng board trong danh sách.
  Widget _buildBoardTile(BoardSummary board) {
    final isOwner = board.ownerId == widget.user.uid;
    final isBusy = _busyBoardIds.contains(board.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => _openBoard(board),
        leading: const CircleAvatar(child: Icon(Icons.dashboard_outlined)),
        title: Text(board.name),
        subtitle: Text(
          board.description.isEmpty
              ? '${board.memberIds.length} thành viên'
              : '${board.description}\n'
                    '${board.memberIds.length} thành viên',
          maxLines: board.description.isEmpty ? 1 : 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: board.description.isNotEmpty,
        trailing: isBusy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : isOwner
            ? PopupMenuButton<_BoardMenuAction>(
                tooltip: 'Thao tác board',
                onSelected: (action) {
                  _handleBoardMenu(board, action);
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _BoardMenuAction.edit,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Sửa thông tin'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _BoardMenuAction.archive,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.archive_outlined),
                      title: Text('Lưu trữ board'),
                    ),
                  ),
                ],
              )
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}

// Các thao tác có trong menu board.
enum _BoardMenuAction { edit, archive }

// ============================================================
// MÀN HÌNH BOARD ĐÃ LƯU TRỮ
// ============================================================

class ArchivedBoardsScreen extends StatefulWidget {
  const ArchivedBoardsScreen({
    required this.user,
    required this.repository,
    super.key,
  });

  final User user;
  final BoardsRepository repository;

  @override
  State<ArchivedBoardsScreen> createState() => _ArchivedBoardsScreenState();
}

class _ArchivedBoardsScreenState extends State<ArchivedBoardsScreen> {
  final Set<String> _busyBoardIds = <String>{};

  // Khôi phục board sau khi người dùng xác nhận.
  Future<void> _restore(BoardSummary board) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Khôi phục board?'),
        content: Text(
          'Board "${board.name}" sẽ xuất hiện lại '
          'trong danh sách chính.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Khôi phục'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted || _busyBoardIds.contains(board.id)) {
      return;
    }

    setState(() {
      _busyBoardIds.add(board.id);
    });

    try {
      await widget.repository.restoreBoard(board.id);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã khôi phục board.')));
      }
    } on FirebaseException catch (error) {
      if (mounted) {
        final message = error.code == 'permission-denied'
            ? 'Chỉ Owner mới có quyền khôi phục board.'
            : 'Không khôi phục được board: '
                  '${error.message ?? error.code}';

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không khôi phục được board: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyBoardIds.remove(board.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Board đã lưu trữ')),
      body: SafeArea(
        child: StreamBuilder<List<BoardSummary>>(
          stream: widget.repository.watchMyBoards(widget.user.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return const _InlineEmptyState(
                icon: Icons.cloud_off_outlined,
                message:
                    'Không tải được board đã lưu trữ. '
                    'Hãy kiểm tra kết nối và thử lại.',
              );
            }

            final archivedBoards = (snapshot.data ?? const <BoardSummary>[])
                .where((board) => board.isArchived)
                .toList(growable: false);

            if (archivedBoards.isEmpty) {
              return const _InlineEmptyState(
                icon: Icons.archive_outlined,
                message: 'Bạn chưa có board nào được lưu trữ.',
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: archivedBoards.length,
              itemBuilder: (context, index) {
                final board = archivedBoards[index];

                final isOwner = board.ownerId == widget.user.uid;

                final isBusy = _busyBoardIds.contains(board.id);

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.archive_outlined),
                    ),
                    title: Text(board.name),
                    subtitle: Text(
                      board.description.isEmpty
                          ? '${board.memberIds.length} thành viên'
                          : '${board.description}\n'
                                '${board.memberIds.length} thành viên',
                    ),
                    isThreeLine: board.description.isNotEmpty,
                    trailing: isBusy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : isOwner
                        ? TextButton.icon(
                            onPressed: () {
                              _restore(board);
                            },
                            icon: const Icon(Icons.unarchive_outlined),
                            label: const Text('Khôi phục'),
                          )
                        : const Tooltip(
                            message: 'Chỉ Owner được khôi phục',
                            child: Icon(Icons.lock_outline),
                          ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ============================================================
// WIDGET TRẠNG THÁI TRỐNG
// ============================================================

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// WIDGET THÔNG BÁO VÀ TẢI LẠI
// ============================================================

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 58,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: loading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(loading ? 'Đang xử lý...' : actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
