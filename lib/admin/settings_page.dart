/// Settings page.
///
/// The status panel now probes Firebase Auth, Firestore, Supabase
/// Storage, and the Gemini API key in real time. Storage counters
/// count actual documents in their respective collections.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_config.dart';
import 'admin_ui.dart';
import 'widgets/admin_badge.dart';
import 'widgets/admin_section.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AdminPageHeader(
                title: 'Settings',
                subtitle:
                    'Live system status, app info and storage usage.',
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final left = _StatusPanel();
                  final right = _AppInfoPanel();
                  if (constraints.maxWidth < 820) {
                    return Column(
                      children: [
                        left,
                        const SizedBox(height: 16),
                        right,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: 16),
                      Expanded(child: right),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              _StoragePanel(),
            ],
          ),
        ),
      );
}

/// One probe row in the status panel.
class _ProbeRow extends StatelessWidget {
  const _ProbeRow({
    required this.name,
    required this.future,
    this.icon,
  });

  final String name;
  final Future<_ProbeResult> future;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ProbeResult>(
      future: future,
      builder: (context, snapshot) {
        // While the future is unresolved but still running, show a neutral
        // "Checking" badge so the user sees the probe is in flight.
        if (snapshot.connectionState != ConnectionState.done) {
          return _StatusTile(
            name: name,
            icon: icon ?? Icons.health_and_safety_outlined,
            label: 'Checking…',
            tone: _Tone.neutral,
          );
        }
        final result = snapshot.data ?? _ProbeResult.down('No result');
        return _StatusTile(
          name: name,
          icon: icon ?? Icons.health_and_safety_outlined,
          label: result.label,
          tone: result.tone,
        );
      },
    );
  }
}

class _StatusPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AdminSection(
        title: 'System status',
        subtitle: 'Live probes — refreshes on each visit.',
        icon: Icons.health_and_safety_outlined,
        child: Column(
          children: [
            _ProbeRow(
              name: 'Firebase Auth',
              icon: Icons.lock_outline,
              future: _probeFirebaseAuth(),
            ),
            const _Divider(),
            _ProbeRow(
              name: 'Firestore',
              icon: Icons.cloud_outlined,
              future: _probeFirestore(),
            ),
            const _Divider(),
            _ProbeRow(
              name: 'Supabase Storage',
              icon: Icons.cloud_sync_outlined,
              future: _probeSupabase(),
            ),
            const _Divider(),
            _ProbeRow(
              name: 'Gemini AI',
              icon: Icons.auto_awesome_outlined,
              future: _probeGemini(),
            ),
            const _Divider(),
            _ProbeRow(
              name: 'Storage',
              icon: Icons.folder_open_outlined,
              future: _probeBuckets(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showKeysDialog(context),
                icon: const Icon(Icons.key_outlined, size: 16),
                label: const Text('Show configured keys'),
              ),
            ),
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 16, color: Color(0xFFE5E7EB));
}

/// One storage counter row that aggregates documents across one or more
/// Firestore collections.
class _CollectionCountRow extends StatelessWidget {
  const _CollectionCountRow({
    required this.label,
    required this.collections,
  });

  final String label;
  final List<String> collections;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<int>>(
      stream: _streamCounts(collections),
      builder: (context, snapshot) {
        final loading = !snapshot.hasData;
        final counts = snapshot.data ?? const [];
        final total = counts.fold<int>(0, (sum, c) => sum + c);
        final detail = loading
            ? '…'
            : counts.length == 1
                ? '${_formatNumber(total)} docs'
                : counts
                    .asMap()
                    .entries
                    .map((e) =>
                        '${collections[e.key]}: ${_formatNumber(e.value)}')
                    .join(' · ');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AdminPalette.heading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminPalette.body,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  _formatNumber(total),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AdminPalette.heading,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AppInfoPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AdminSection(
        title: 'App info',
        icon: Icons.info_outline,
        child: Column(
          children: const [
            _InfoRow(label: 'App version', value: '1.0.0'),
            _InfoRow(label: 'Build', value: '1'),
            _InfoRow(label: 'Package', value: 'com.scholarbird.app'),
            _InfoRow(label: 'Environment', value: 'Production'),
          ],
        ),
      );
}

class _StoragePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AdminSection(
        title: 'Storage usage',
        subtitle: 'Live Firestore document counts.',
        icon: Icons.storage_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _CollectionCountRow(
              label: 'Scholarships',
              collections: ['scholarships'],
            ),
            _CollectionCountRow(
              label: 'Applications',
              collections: ['applications'],
            ),
            _CollectionCountRow(
              label: 'Users',
              collections: ['users'],
            ),
            _CollectionCountRow(
              label: 'Mentors',
              collections: ['mentors'],
            ),
            _CollectionCountRow(
              label: 'Activity logs',
              collections: ['activity_logs'],
            ),
          ],
        ),
      );
}

// ─── Probes ──────────────────────────────────────────────────────────────

class _ProbeResult {
  const _ProbeResult(this.label, this.tone);
  factory _ProbeResult.up(String label) => _ProbeResult(label, _Tone.success);
  factory _ProbeResult.warn(String label) =>
      _ProbeResult(label, _Tone.warning);
  factory _ProbeResult.down(String label) => _ProbeResult(label, _Tone.danger);

  final String label;
  final _Tone tone;
}

Future<_ProbeResult> _probeFirebaseAuth() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      return _ProbeResult.up('Signed in (${user.email ?? user.uid})');
    }
    return _ProbeResult.warn('Signed out');
  } catch (e) {
    return _ProbeResult.down('Error');
  }
}

Future<_ProbeResult> _probeFirestore() async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('scholarships')
        .limit(1)
        .get()
        .timeout(const Duration(seconds: 5));
    return _ProbeResult.up('Online · ${doc.docs.length} read');
  } on TimeoutException {
    return _ProbeResult.warn('Slow');
  } catch (e) {
    return _ProbeResult.down('Offline');
  }
}

Future<_ProbeResult> _probeSupabase() async {
  try {
    final client = Supabase.instance.client;
    final files = await client.storage
        .from(SupabaseConfig.profileImagesBucket)
        .list()
        .timeout(const Duration(seconds: 6));
    final count = files.length;
    return _ProbeResult.up('Online · $count obj');
  } on TimeoutException {
    return _ProbeResult.warn('Slow');
  } catch (e) {
    return _ProbeResult.down('Offline');
  }
}

Future<_ProbeResult> _probeGemini() async {
  try {
    final key = (dotenv.env['GEMINI_API_KEY'] ??
            dotenv.env['GOOGLE_API_KEY'])
        ?.trim();
    if (key == null || key.isEmpty || key == 'YOUR_KEY') {
      return _ProbeResult.warn('Not configured');
    }
    return _ProbeResult.up('Key set');
  } catch (_) {
    return _ProbeResult.down('Error');
  }
}

Future<_ProbeResult> _probeBuckets() async {
  try {
    final client = Supabase.instance.client;
    final buckets = [
      SupabaseConfig.profileImagesBucket,
      SupabaseConfig.mentorImagesBucket,
      SupabaseConfig.scholarshipBannersBucket,
      SupabaseConfig.adminImagesBucket,
    ];
    int total = 0;
    for (final name in buckets) {
      try {
        final files = await client.storage
            .from(name)
            .list()
            .timeout(const Duration(seconds: 4));
        total += files.length;
      } catch (_) {
        // Ignore individual bucket errors so one failure doesn't kill the probe.
      }
    }
    return _ProbeResult.up('$total objects');
  } on TimeoutException {
    return _ProbeResult.warn('Slow');
  } catch (_) {
    return _ProbeResult.down('Error');
  }
}

void _showKeysDialog(BuildContext context) {
  final auth = FirebaseAuth.instance;
  final supabaseUrl = SupabaseConfig.url;
  final anon = SupabaseConfig.anonKey;
  final gemini =
      (dotenv.env['GEMINI_API_KEY'] ?? dotenv.env['GOOGLE_API_KEY'])?.trim();
  final geminiStatus = (gemini == null || gemini.isEmpty || gemini == 'YOUR_KEY')
      ? 'Not set'
      : '${gemini.substring(0, 4)}…${gemini.substring(gemini.length - 4)}';

  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Configured services'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _kv('Firebase project', auth.app.options.projectId),
            _kv('Supabase URL', supabaseUrl),
            _kv('Supabase anon', _mask(anon)),
            _kv('Gemini API key', geminiStatus),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

Widget _kv(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: AdminPalette.heading, fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(color: AdminPalette.body),
            ),
            TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );

String _mask(String? value) {
  if (value == null || value.isEmpty) return '—';
  if (value.length <= 8) return value;
  return '${value.substring(0, 4)}…${value.substring(value.length - 4)}';
}

Stream<List<int>> _streamCounts(List<String> collections) {
  final controller = StreamController<List<int>>();
  void emit() async {
    final counts = <int>[];
    for (final name in collections) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection(name)
            .count()
            .get()
            .timeout(const Duration(seconds: 6));
        counts.add(snap.count ?? 0);
      } catch (_) {
        counts.add(0);
      }
    }
    controller.add(counts);
  }

  emit();
  // Refresh every 30 seconds while the page is open.
  final timer = Timer.periodic(const Duration(seconds: 30), (_) => emit());
  controller.onCancel = timer.cancel;
  return controller.stream;
}

String _formatNumber(int n) {
  if (n < 1000) return n.toString();
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '${(n / 1000000).toStringAsFixed(1)}M';
}

// ─── Shared widgets ──────────────────────────────────────────────────────

enum _Tone { success, warning, danger, neutral }

extension on _Tone {
  Color get color {
    switch (this) {
      case _Tone.success:
        return const Color(0xFF16A34A);
      case _Tone.warning:
        return const Color(0xFFD97706);
      case _Tone.danger:
        return const Color(0xFFDC2626);
      case _Tone.neutral:
        return const Color(0xFF6B7280);
    }
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.name,
    required this.icon,
    required this.label,
    required this.tone,
  });

  final String name;
  final IconData icon;
  final String label;
  final _Tone tone;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AdminPalette.body),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AdminPalette.heading,
                ),
              ),
            ),
            AdminBadge(label: label, color: tone.color, dense: true),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(color: AdminPalette.body)),
            ),
            Text(value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AdminPalette.heading,
                )),
          ],
        ),
      );
}
