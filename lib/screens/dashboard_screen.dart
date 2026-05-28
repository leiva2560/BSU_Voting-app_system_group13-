import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'election_detail_screen.dart';
import 'login_screen.dart';
import 'results_screen.dart';
import 'admin/admin_panel_screen.dart';

class ElectionDashboardScreen extends StatelessWidget {
  const ElectionDashboardScreen({super.key, required this.currentUser});

  final User? currentUser;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser?.uid)
          .get(),
      builder: (context, userSnap) {
        final userData =
            userSnap.hasData && userSnap.data!.exists
                ? userSnap.data!.data() as Map<String, dynamic>
                : <String, dynamic>{};
        final name = userData['name'] ??
            currentUser?.displayName ??
            currentUser?.email ??
            'Student';
        final regNo = userData['registrationNumber'] ?? '';
        final isAdmin = userData['role'] == 'admin';

        return Scaffold(
          backgroundColor: colorScheme.surface,

          // ── Drawer sidebar ──────────────────────────────────────────────
          drawer: Drawer(
            child: Column(
              children: [
                // Header
                UserAccountsDrawerHeader(
                  decoration: BoxDecoration(color: colorScheme.primary),
                  accountName: Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  accountEmail: Text(regNo.isNotEmpty
                      ? 'ID: $regNo'
                      : (currentUser?.email ?? '')),
                  currentAccountPicture: CircleAvatar(
                    backgroundColor: colorScheme.primaryContainer,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'S',
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary),
                    ),
                  ),
                ),

                // Nav items
                _DrawerItem(
                  icon: Icons.how_to_vote_outlined,
                  label: 'Elections',
                  onTap: () => Navigator.pop(context),
                ),
                _DrawerItem(
                  icon: Icons.bar_chart_outlined,
                  label: 'Results',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            ResultsScreen(currentUser: currentUser)));
                  },
                ),
                if (isAdmin) ...[
                  const Divider(indent: 16, endIndent: 16),
                  _DrawerItem(
                    icon: Icons.admin_panel_settings_outlined,
                    label: 'Admin Panel',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              AdminPanelScreen(currentUser: currentUser!)));
                    },
                  ),
                ],
                const Spacer(),
                const Divider(),
                // Logout at bottom
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Logout',
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.pop(context);
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(
                              builder: (_) => const LoginScreen()),
                          (_) => false);
                    }
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // ── AppBar ──────────────────────────────────────────────────────
          appBar: AppBar(
            backgroundColor: colorScheme.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            title: const Text('Elections',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            actions: [
              IconButton(
                icon: const Icon(Icons.bar_chart, color: Colors.white),
                tooltip: 'Results',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ResultsScreen(currentUser: currentUser))),
              ),
              if (isAdmin)
                IconButton(
                  icon: const Icon(Icons.admin_panel_settings,
                      color: Colors.white),
                  tooltip: 'Admin Panel',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          AdminPanelScreen(currentUser: currentUser!))),
                ),
            ],
          ),

          // ── Body ────────────────────────────────────────────────────────
          body: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('elections')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final now = DateTime.now();
              final all = snapshot.data!.docs;

              final active = all.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final s = (data['startsAt'] as Timestamp).toDate();
                final e = (data['endsAt'] as Timestamp).toDate();
                return now.isAfter(s) && now.isBefore(e);
              }).toList();

              final upcoming = all.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return now.isBefore(
                    (data['startsAt'] as Timestamp).toDate());
              }).toList();

              final completed = all.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return now
                    .isAfter((data['endsAt'] as Timestamp).toDate());
              }).toList();

              return RefreshIndicator(
                onRefresh: () async {},
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    // Welcome card
                    _WelcomeCard(name: name, regNo: regNo, isAdmin: isAdmin),
                    const SizedBox(height: 20),

                    // Active
                    _SectionHeader(
                        icon: Icons.how_to_vote,
                        label: 'Active Elections',
                        color: Colors.green,
                        count: active.length),
                    const SizedBox(height: 8),
                    if (active.isEmpty)
                      _EmptyState('No active elections right now.')
                    else
                      ...active.map((d) => _ElectionCard(
                          doc: d, currentUser: currentUser, status: 'active')),

                    const SizedBox(height: 20),

                    // Upcoming
                    _SectionHeader(
                        icon: Icons.schedule,
                        label: 'Upcoming Elections',
                        color: Colors.blue,
                        count: upcoming.length),
                    const SizedBox(height: 8),
                    if (upcoming.isEmpty)
                      _EmptyState('No upcoming elections.')
                    else
                      ...upcoming.map((d) => _ElectionCard(
                          doc: d,
                          currentUser: currentUser,
                          status: 'upcoming')),

                    const SizedBox(height: 20),

                    // Completed
                    _SectionHeader(
                        icon: Icons.check_circle_outline,
                        label: 'Completed Elections',
                        color: Colors.grey,
                        count: completed.length),
                    const SizedBox(height: 8),
                    if (completed.isEmpty)
                      _EmptyState('No completed elections.')
                    else
                      ...completed.map((d) => _ElectionCard(
                          doc: d,
                          currentUser: currentUser,
                          status: 'completed')),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ── Drawer item ─────────────────────────────────────────────────────────────
class _DrawerItem extends StatelessWidget {
  const _DrawerItem(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label,
          style: const TextStyle(fontWeight: FontWeight.w500)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }
}

// ── Welcome card ─────────────────────────────────────────────────────────────
class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard(
      {required this.name, required this.regNo, required this.isAdmin});
  final String name;
  final String regNo;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.primaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white24,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'S',
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome back,',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13)),
                Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                if (regNo.isNotEmpty)
                  Text('ID: $regNo',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12)),
              ],
            ),
          ),
          if (isAdmin)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('Admin',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}

// ── Section header ───────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.icon,
      required this.label,
      required this.color,
      required this.count});
  final IconData icon;
  final String label;
  final Color color;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Text(label,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color)),
        const Spacer(),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12)),
          child: Text('$count',
              style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ),
      ],
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Text(message,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Election card ────────────────────────────────────────────────────────────
class _ElectionCard extends StatelessWidget {
  const _ElectionCard(
      {required this.doc,
      required this.currentUser,
      required this.status});
  final QueryDocumentSnapshot doc;
  final User? currentUser;
  final String status;

  Color get _statusColor {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'upcoming':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  IconData get _statusIcon {
    switch (status) {
      case 'active':
        return Icons.how_to_vote;
      case 'upcoming':
        return Icons.schedule;
      default:
        return Icons.check_circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final startsAt = (data['startsAt'] as Timestamp).toDate();
    final endsAt = (data['endsAt'] as Timestamp).toDate();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ElectionDetailScreen(
                currentUser: currentUser,
                electionId: doc.id,
                electionData: data))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_statusIcon, color: _statusColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['title'] ?? 'Untitled',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(data['description'] ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 12)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 11, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        status == 'upcoming'
                            ? 'Starts ${_fmt(startsAt)}'
                            : status == 'active'
                                ? 'Ends ${_fmt(endsAt)}'
                                : 'Ended ${_fmt(endsAt)}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[500]),
                      ),
                    ]),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status[0].toUpperCase() + status.substring(1),
                  style: TextStyle(
                      color: _statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';
}
