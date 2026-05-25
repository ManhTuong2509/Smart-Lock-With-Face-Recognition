import 'package:app_smart_lock/screens/adduser.dart';
import 'package:app_smart_lock/services/smart_lock_cloud_service.dart';
import 'package:flutter/material.dart';

class ManagerUserScreen extends StatefulWidget {
  const ManagerUserScreen({super.key});

  @override
  State<ManagerUserScreen> createState() => _ManagerUserScreenState();
}

class _ManagerUserScreenState extends State<ManagerUserScreen> {
  final SmartLockCloudService _cloudService = SmartLockCloudService.instance;

  List<RegisteredFaceUser> _members = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final members = await _cloudService.fetchUsers();
      if (!mounted) return;
      setState(() {
        _members = members;
        _isLoading = false;
      });
    } on SmartLockCloudException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.message;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '$error';
        _isLoading = false;
      });
    }
  }

  Future<void> _openAddMember() async {
    final newMember = await Navigator.of(context).push<AddedMember>(
      MaterialPageRoute(builder: (_) => const AddUserScreen()),
    );

    if (newMember == null || newMember.name.trim().isEmpty) return;

    await _loadMembers();
  }

  Future<void> _confirmRemoveMember(int index) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 34),
          child: Container(
            height: 166,
            padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
            decoration: BoxDecoration(
              color: const Color(0xFFB8B8B8),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Xác nhận xóa thành viên?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'serif',
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ConfirmButton(
                      label: 'Hủy',
                      color: const Color(0xFFFF0505),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    _ConfirmButton(
                      label: 'Xóa',
                      color: const Color(0xFF00F736),
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldDelete != true) return;

    final member = _members[index];
    try {
      await _cloudService.deleteUsersByName(member.userName);
      await _loadMembers();
    } on SmartLockCloudException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Member Family',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'serif',
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: _isLoading ? null : _loadMembers,
                  icon: const Icon(Icons.refresh),
                  color: Colors.white,
                  tooltip: 'Refresh',
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: SizedBox(
                  width: 224,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _openAddMember,
                    icon: const Icon(Icons.add, size: 30),
                    label: const Text('add member'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF47F91),
                      foregroundColor: Colors.black,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'serif',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFA8A8A8),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(22, 10, 22, 8),
                        child: Text(
                          'Danh sách thành viên',
                          style: TextStyle(
                            color: Color(0xFF595959),
                            fontSize: 18,
                            fontFamily: 'serif',
                          ),
                        ),
                      ),
                      Expanded(
                        child: _buildMemberList(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFF47F91)),
      );
    }

    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return _StateMessage(
        message: errorMessage,
        actionLabel: 'Thử lại',
        onPressed: _loadMembers,
      );
    }

    if (_members.isEmpty) {
      return const _StateMessage(message: 'Chưa có thành viên nào');
    }

    return RefreshIndicator(
      onRefresh: _loadMembers,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 18),
        itemCount: _members.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          return _MemberTile(
            member: _members[index],
            onDelete: () => _confirmRemoveMember(index),
          );
        },
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ConfirmButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 40,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            fontFamily: 'serif',
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final RegisteredFaceUser member;
  final VoidCallback onDelete;

  const _MemberTile({required this.member, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final imageBytes = member.imageBytes;
    final hasPhoto = imageBytes != null && imageBytes.isNotEmpty;

    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFFE4E4E4),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 23,
            backgroundColor: Colors.white,
            backgroundImage: imageBytes == null || imageBytes.isEmpty
                ? null
                : MemoryImage(imageBytes),
            child: hasPhoto
                ? null
                : const Icon(Icons.person, color: Color(0xFF777777), size: 28),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              member.userName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                fontFamily: 'serif',
              ),
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            color: Colors.black,
            iconSize: 30,
            tooltip: 'Delete member',
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final VoidCallback? onPressed;

  const _StateMessage({
    required this.message,
    this.actionLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF595959),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: 'serif',
              ),
            ),
            if (actionLabel != null && onPressed != null) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF47F91),
                  foregroundColor: Colors.black,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
