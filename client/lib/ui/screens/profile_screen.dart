import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stealth/supabase_service.dart';
// import 'package:stealth/ui/widgets/qr_code_display.dart';
import 'package:stealth/test_account_selection_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
// import 'package:image_gallery_saver/image_gallery_saver.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  String? _userId;
  String? _nickname;
  final TextEditingController _nicknameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    _userId = await _supabaseService.getUserId();
    _nickname = await _supabaseService.getNickname();
    _nicknameController.text = _nickname ?? '';
    setState(() {});
  }

  Future<void> _saveNickname() async {
    if (_nicknameController.text.trim().isNotEmpty) {
      // await _supabaseService.updateNickname(_nicknameController.text.trim());
      setState(() {
        _nickname = _nicknameController.text.trim();
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nickname updated!')),
      );
    }
  }

  Future<void> _exportPrivateKey() async {
    final privateKey = null; // await _supabaseService.getPrivateKey();
    if (privateKey != null) {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/secure-chat-key.txt');
      await file.writeAsString(privateKey);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Private key exported to ${file.path}')),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No private key found.')),
      );
    }
  }

  Future<void> _importPrivateKey() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'key'],
    );
    if (result != null && result.files.single.path != null) {
      final File file = File(result.files.single.path!);
      final String content = await file.readAsString();
      // await _supabaseService.setPrivateKey(content.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Private key imported successfully.')),
      );
    }
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manage your account and security settings',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),

            // Personal Information Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personal Information',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Your nickname is only stored locally',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    const Text('Nickname'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nicknameController,
                            decoration: const InputDecoration(
                              hintText: 'Enter your nickname',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _saveNickname,
                          icon: const Icon(Icons.save),
                          label: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Your User ID Section
            _userId != null
                ? Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text('User ID: $_userId'),
                        SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: _userId!));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('User ID copied to clipboard!')),
                            );
                          },
                          child: Text('Copy User ID'),
                        ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(),
            const SizedBox(height: 24),

            // Security Keys Card
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Security Keys',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Export your private key for backup or import to restore',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _exportPrivateKey,
                        icon: const Icon(Icons.download),
                        label: const Text('Export Private Key'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _importPrivateKey,
                        icon: const Icon(Icons.upload),
                        label: const Text('Import Private Key'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '⚠️ Never share your private key with anyone. Keep it safe!',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 32),
            Center(
              child: ElevatedButton.icon(
                icon: Icon(Icons.logout),
                label: Text('Сменить пользователя'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withOpacity(0.85),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  minimumSize: Size(0, 48),
                ),
                onPressed: () async {
                  await _supabaseService.logout();
                  if (!mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => TestAccountSelectionScreen()),
                    (_) => false,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}