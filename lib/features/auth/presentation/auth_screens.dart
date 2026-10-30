import 'package:flutter/material.dart';

import '../data/auth_repository.dart';

const _purple = Color(0xFF5145E8);
const _page = Color(0xFFF4F5FA);
const _ink = Color(0xFF20212B);
const _muted = Color(0xFF626779);

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    required this.auth,
    required this.firebaseSetupMessage,
    super.key,
  });

  final AuthRepository auth;
  final String? firebaseSetupMessage;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPasswordReset() async {
    final email = await showDialog<String>(
      context: context,
      builder: (context) => PasswordResetDialog(
        auth: widget.auth,
        initialEmail: _emailController.text.trim(),
      ),
    );
    if (email != null && mounted) {
      _emailController.text = email;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nếu email đã đăng ký, hướng dẫn đặt lại mật khẩu sẽ được gửi đến hộp thư.',
          ),
        ),
      );
    }
  }

  Future<void> _openRegistration() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => RegisterScreen(
          auth: widget.auth,
          firebaseSetupMessage: widget.firebaseSetupMessage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _page,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 44, 20, 22),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _BrandMark(),
                            const SizedBox(height: 8),
                            const Text(
                              'Smart Todo',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 23,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Đăng nhập để tiếp tục quản lý công việc của bạn.',
                              style: TextStyle(color: _muted, fontSize: 13),
                            ),
                            if (widget.firebaseSetupMessage
                                case final message?) ...[
                              const SizedBox(height: 16),
                              _InfoBanner(message: message),
                            ],
                            if (_error case final message?) ...[
                              const SizedBox(height: 14),
                              _ErrorBanner(message: message),
                            ],
                            const SizedBox(height: 18),
                            const _FieldLabel('Email'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              decoration: _fieldDecoration(
                                hintText: 'nguyenvana@gmail.com',
                              ),
                              validator: _validateEmail,
                            ),
                            const SizedBox(height: 14),
                            const _FieldLabel('Mật khẩu'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) => _signIn(),
                              decoration: _fieldDecoration(
                                suffixIcon: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'Hiện mật khẩu'
                                      : 'Ẩn mật khẩu',
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: _muted,
                                    size: 20,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.isEmpty
                                  ? 'Vui lòng nhập mật khẩu.'
                                  : null,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _busy ? null : _openPasswordReset,
                                style: TextButton.styleFrom(
                                  foregroundColor: _purple,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  minimumSize: const Size(0, 38),
                                ),
                                child: const Text(
                                  'Quên mật khẩu?',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            _PrimaryButton(
                              label: 'Đăng nhập',
                              busy: _busy,
                              onPressed: _signIn,
                            ),
                            const SizedBox(height: 100),
                            const SizedBox(height: 44),
                            Center(
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text(
                                    'Chưa có tài khoản? ',
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _busy ? null : _openRegistration,
                                    child: const Text(
                                      'Đăng ký tài khoản',
                                      style: TextStyle(
                                        color: _purple,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    required this.auth,
    required this.firebaseSetupMessage,
    super.key,
  });

  final AuthRepository auth;
  final String? firebaseSetupMessage;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.register(
        displayName: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (mounted) Navigator.of(context).pop();
    } on AuthFailure catch (error) {
      if (!mounted) return;
      if (error.message.toLowerCase().contains('email này đã được đăng ký')) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Email đã tồn tại'),
            content: Text(
              'Email ${_emailController.text.trim()} đã được dùng cho một tài khoản khác. Bạn có thể đăng nhập hoặc dùng email khác.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Dùng email khác'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Text('Đăng nhập'),
              ),
            ],
          ),
        );
      } else {
        setState(() => _error = error.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _page,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                tooltip: 'Quay lại',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.arrow_back),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 40,
                                  height: 40,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Tạo tài khoản',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 23,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Nhập họ tên, email và mật khẩu để bắt đầu.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            if (widget.firebaseSetupMessage
                                case final message?) ...[
                              const SizedBox(height: 14),
                              _InfoBanner(message: message),
                            ],
                            if (_error case final message?) ...[
                              const SizedBox(height: 12),
                              _ErrorBanner(message: message),
                            ],
                            const SizedBox(height: 16),
                            const _FieldLabel('Họ và tên'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _nameController,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.name],
                              decoration: _fieldDecoration(
                                hintText: 'Nguyễn Văn A',
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Vui lòng nhập họ tên.'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            const _FieldLabel('Email'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.newUsername],
                              decoration: _fieldDecoration(
                                hintText: 'nguyenvana@gmail.com',
                              ),
                              validator: _validateEmail,
                            ),
                            const SizedBox(height: 12),
                            const _FieldLabel('Mật khẩu'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: _fieldDecoration(
                                hintText: 'Tối thiểu 8 ký tự',
                                suffixIcon: _VisibilityButton(
                                  visible: _obscurePassword,
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  value == null || value.length < 8
                                  ? 'Mật khẩu phải có tối thiểu 8 ký tự.'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            const _FieldLabel('Xác nhận mật khẩu'),
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: _confirmController,
                              obscureText: _obscureConfirm,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _register(),
                              decoration: _fieldDecoration(
                                suffixIcon: _VisibilityButton(
                                  visible: _obscureConfirm,
                                  onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm,
                                  ),
                                ),
                              ),
                              validator: (value) =>
                                  value != _passwordController.text
                                  ? 'Mật khẩu xác nhận không khớp.'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            _PrimaryButton(
                              label: 'Đăng ký',
                              busy: _busy,
                              onPressed: _register,
                            ),
                            const SizedBox(height: 44),
                            Center(
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  const Text(
                                    'Đã có tài khoản? ',
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _busy
                                        ? null
                                        : () => Navigator.pop(context),
                                    child: const Text(
                                      'Đăng nhập',
                                      style: TextStyle(
                                        color: _purple,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PasswordResetDialog extends StatefulWidget {
  const PasswordResetDialog({
    required this.auth,
    required this.initialEmail,
    super.key,
  });

  final AuthRepository auth;
  final String initialEmail;

  @override
  State<PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<PasswordResetDialog> {
  late final TextEditingController _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.sendPasswordResetEmail(_emailController.text);
      if (mounted) Navigator.of(context).pop(_emailController.text.trim());
    } on AuthFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Đặt lại mật khẩu'),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Nhập email để nhận hướng dẫn đặt lại mật khẩu.'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: _fieldDecoration(labelText: 'Email'),
            validator: _validateEmail,
          ),
          if (_error case final message?) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Hủy'),
      ),
      FilledButton(
        onPressed: _busy ? null : _send,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Gửi email'),
      ),
    ],
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _purple,
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Icon(Icons.task_alt_rounded, color: Colors.white, size: 29),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: _muted,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
  );
}

class _VisibilityButton extends StatelessWidget {
  const _VisibilityButton({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: visible ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
    onPressed: onPressed,
    icon: Icon(
      visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      color: _muted,
      size: 20,
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _purple,
        disabledBackgroundColor: _purple.withValues(alpha: .65),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label, style: const TextStyle(fontSize: 13)),
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFE7E5FF),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(message, style: const TextStyle(fontSize: 12)),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE1E1),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Colors.red, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

InputDecoration _fieldDecoration({
  String? labelText,
  String? hintText,
  Widget? suffixIcon,
}) => InputDecoration(
  labelText: labelText,
  hintText: hintText,
  filled: true,
  fillColor: Colors.white,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  suffixIcon: suffixIcon,
  suffixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 42),
  hintStyle: const TextStyle(color: Color(0xFF85899A), fontSize: 13),
  labelStyle: const TextStyle(color: _muted, fontSize: 13),
  errorStyle: const TextStyle(color: Colors.red, fontSize: 10, height: 1.2),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: const BorderSide(color: Color(0xFFD9DCE6)),
  ),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: const BorderSide(color: Color(0xFFD9DCE6)),
  ),
  focusedBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: const BorderSide(color: _purple, width: 1.4),
  ),
  errorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: const BorderSide(color: Colors.red, width: 1.2),
  ),
  focusedErrorBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(9),
    borderSide: const BorderSide(color: Colors.red, width: 1.2),
  ),
);

String? _validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Vui lòng nhập email.';
  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
    return 'Email không đúng định dạng.';
  }
  return null;
}
