import 'package:flutter/material.dart';
import 'package:stealth/supabase_service.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../widgets/glass_app_bar.dart';
import '../constants/app_colors.dart';
import '../constants/app_spacing.dart';
import '../constants/app_typography.dart';
import '../components/glass_container.dart';

class LiquidProfileScreen extends StatefulWidget {
  const LiquidProfileScreen({super.key});

  @override
  State<LiquidProfileScreen> createState() => _LiquidProfileScreenState();
}

class _LiquidProfileScreenState extends State<LiquidProfileScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  String _nickname = '';
  String _userId = '';
  String _qrData = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final userId = await _supabaseService.getUserId();
      final nickname = await _supabaseService.getUserNickname();
      final qrData = _supabaseService.generateQRCode(userId ?? '');
      
      if (!mounted) return;
      
      setState(() {
        _userId = userId ?? '';
        _nickname = nickname ?? 'User';
        _qrData = qrData;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.backgroundPrimary,
              AppColors.backgroundSecondary,
              AppColors.backgroundPrimary,
            ],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    children: [
                      Text(
                        'Profile',
                        style: AppTypography.largeTitle.copyWith(
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      _buildProfileHeader(),
                      const SizedBox(height: AppSpacing.xxl),
                      _buildQRSection(),
                      const SizedBox(height: AppSpacing.xxl),
                      _buildSettingsSection(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return GlassCard(
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.liquidGradient4,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.liquidGradient4.first.withOpacity(0.4),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(
              child: Text(
                _nickname.isNotEmpty ? _nickname[0].toUpperCase() : 'U',
                style: AppTypography.largeTitle.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 48,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            _nickname,
            style: AppTypography.title1.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'ID: ${_userId.substring(0, 8)}...',
            style: AppTypography.caption1.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQRSection() {
    return GlassCard(
      child: Column(
        children: [
          Text(
            'Your QR Code',
            style: AppTypography.title2.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_qrData.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: QrImageView(
                data: _qrData,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Share this code with others to add you as a contact',
            style: AppTypography.caption1.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection() {
    return Column(
      children: [
        _buildSettingItem(
          icon: Icons.edit,
          title: 'Edit Profile',
          onTap: () {
            // Navigate to edit profile
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildSettingItem(
          icon: Icons.notifications,
          title: 'Notifications',
          onTap: () {
            // Navigate to notifications settings
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildSettingItem(
          icon: Icons.security,
          title: 'Privacy & Security',
          onTap: () {
            // Navigate to privacy settings
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildSettingItem(
          icon: Icons.help,
          title: 'Help & Support',
          onTap: () {
            // Navigate to help
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        _buildSettingItem(
          icon: Icons.info,
          title: 'About',
          onTap: () {
            // Show about dialog
          },
        ),
      ],
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return GlassCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.liquidGradient3,
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(
              icon,
              color: AppColors.textPrimary,
              size: AppSpacing.iconMd,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              title,
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
