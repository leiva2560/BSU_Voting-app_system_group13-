import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../src/models.dart';
import '../login_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key, required this.currentUser});
  final firebase_auth.User currentUser;

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  int _selectedIndex = 0; // 0=Elections, 1=Candidates, 2=Admins, 3=Reports, 4=Users

  // Election form
  final _electionFormKey = GlobalKey<FormState>();
  final _electionTitleCtrl = TextEditingController();
  final _electionDescCtrl = TextEditingController();
  final _electionStartCtrl = TextEditingController();
  final _electionEndCtrl = TextEditingController();
  final _electionPositionsCtrl = TextEditingController();

  // Candidate form
  final _candidateFormKey = GlobalKey<FormState>();
  final _candidateNameCtrl = TextEditingController();
  final _candidatePositionCtrl = TextEditingController();
  final _candidateBioCtrl = TextEditingController();

  // Admin form
  final _adminFormKey = GlobalKey<FormState>();
  final _adminNameCtrl = TextEditingController();
  final _adminEmailCtrl = TextEditingController();
  final _adminRegCtrl = TextEditingController();
  final _adminPasswordCtrl = TextEditingController();
  bool _obscureAdminPassword = true;

  XFile? _selectedPhoto;
  String? _selectedElectionId;
  bool _isUploading = false;
  bool _isLoading = false;
  double _uploadProgress = 0.0;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // Explicit bucket prevents object-not-found when Android SDK
  // fails to resolve the bucket from google-services.json
  final FirebaseStorage _storage = FirebaseStorage.instanceFor(
      bucket: 'gs://bsuvotingapp.firebasestorage.app');
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _electionTitleCtrl.dispose();
    _electionDescCtrl.dispose();
    _electionStartCtrl.dispose();
    _electionEndCtrl.dispose();
    _electionPositionsCtrl.dispose();
    _candidateNameCtrl.dispose();
    _candidatePositionCtrl.dispose();
    _candidateBioCtrl.dispose();
    _adminNameCtrl.dispose();
    _adminEmailCtrl.dispose();
    _adminRegCtrl.dispose();
    _adminPasswordCtrl.dispose();
    super.dispose();
  }

  // ── Photo picker ──────────────────────────────────────────────────────────
  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
          source: source, maxWidth: 800, maxHeight: 800, imageQuality: 85);
      if (photo != null && mounted) setState(() => _selectedPhoto = photo);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking photo: $e')));
    }
  }

  void _showPhotoPicker() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.camera_alt)),
              title: const Text('Take a Photo'),
              onTap: () { Navigator.pop(context); _pickPhoto(ImageSource.camera); },
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.photo_library)),
              title: const Text('Choose from Gallery'),
              onTap: () { Navigator.pop(context); _pickPhoto(ImageSource.gallery); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Encode photo to base64 for direct Firestore storage ──────────────────
  Future<String?> _encodePhotoToBase64() async {
    if (_selectedPhoto == null) return null;
    try {
      final Uint8List bytes = await _selectedPhoto!.readAsBytes();
      if (bytes.isEmpty) throw Exception('Selected photo file is empty.');
      // Encode as base64 string — stored directly in Firestore document
      final String base64String = base64Encode(bytes);
      debugPrint('Photo encoded: ${bytes.length} bytes → ${base64String.length} chars base64');
      return base64String;
    } catch (e) {
      debugPrint('Photo encode error: $e');
      rethrow;
    }
  }

  // ── Delete election ───────────────────────────────────────────────────────
  Future<void> _deleteElection(String electionId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Colors.red),
          SizedBox(width: 8),
          Text('Delete Election'),
        ]),
        content: Text(
            'Delete "$title"?\n\nThis will also delete all candidates and votes for this election. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      // Delete candidates subcollection
      final candSnap = await _firestore
          .collection('elections').doc(electionId).collection('candidates').get();
      for (final d in candSnap.docs) { await d.reference.delete(); }
      // Delete votes subcollection
      final votesSnap = await _firestore
          .collection('elections').doc(electionId).collection('votes').get();
      for (final d in votesSnap.docs) { await d.reference.delete(); }
      // Delete election
      await _firestore.collection('elections').doc(electionId).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Election deleted.'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  // ── Edit election ─────────────────────────────────────────────────────────
  Future<void> _editElection(String electionId, Map<String, dynamic> data) async {
    final titleCtrl = TextEditingController(text: data['title'] ?? '');
    final descCtrl = TextEditingController(text: data['description'] ?? '');
    final startCtrl = TextEditingController(
        text: (data['startsAt'] as Timestamp).toDate().toString().substring(0, 10));
    final endCtrl = TextEditingController(
        text: (data['endsAt'] as Timestamp).toDate().toString().substring(0, 10));
    final posCtrl = TextEditingController(
        text: (data['positions'] as List? ?? []).join(', '));
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Election'),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 10),
              TextFormField(controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2),
              const SizedBox(height: 10),
              TextFormField(controller: startCtrl,
                  decoration: const InputDecoration(labelText: 'Start Date (YYYY-MM-DD)'),
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 10),
              TextFormField(controller: endCtrl,
                  decoration: const InputDecoration(labelText: 'End Date (YYYY-MM-DD)'),
                  validator: (v) => v!.trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 10),
              TextFormField(controller: posCtrl,
                  decoration: const InputDecoration(labelText: 'Positions (comma separated)')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final startsAt = DateTime.tryParse(startCtrl.text.trim());
              final endsAt = DateTime.tryParse(endCtrl.text.trim());
              if (startsAt == null || endsAt == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid date format.')));
                return;
              }
              final positions = posCtrl.text
                  .split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
              await _firestore.collection('elections').doc(electionId).update({
                'title': titleCtrl.text.trim(),
                'description': descCtrl.text.trim(),
                'startsAt': Timestamp.fromDate(startsAt),
                'endsAt': Timestamp.fromDate(endsAt),
                'positions': positions,
                'updatedAt': FieldValue.serverTimestamp(),
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    titleCtrl.dispose(); descCtrl.dispose(); startCtrl.dispose();
    endCtrl.dispose(); posCtrl.dispose();
  }

  // ── Delete candidate ──────────────────────────────────────────────────────
  Future<void> _deleteCandidate(
      String electionId, String candidateId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Colors.red),
          SizedBox(width: 8),
          Text('Delete Candidate'),
        ]),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _firestore.collection('elections').doc(electionId)
          .collection('candidates').doc(candidateId).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Candidate deleted.'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  // ── Edit candidate ────────────────────────────────────────────────────────
  Future<void> _editCandidate(
      String electionId, String candidateId, Map<String, dynamic> data) async {
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final posCtrl = TextEditingController(text: data['position'] ?? '');
    final bioCtrl = TextEditingController(text: data['bio'] ?? '');
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Edit Candidate'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null),
            const SizedBox(height: 10),
            TextFormField(controller: posCtrl,
                decoration: const InputDecoration(labelText: 'Position'),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null),
            const SizedBox(height: 10),
            TextFormField(controller: bioCtrl,
                decoration: const InputDecoration(labelText: 'Bio'),
                maxLines: 3),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await _firestore.collection('elections').doc(electionId)
                  .collection('candidates').doc(candidateId).update({
                'name': nameCtrl.text.trim(),
                'position': posCtrl.text.trim(),
                'bio': bioCtrl.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    nameCtrl.dispose(); posCtrl.dispose(); bioCtrl.dispose();
  }

  // ── Reset votes ───────────────────────────────────────────────────────────
  Future<void> _resetVotes(String electionId, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.refresh, color: Colors.orange),
          SizedBox(width: 8),
          Text('Reset Votes'),
        ]),
        content: Text('Reset all votes for "$title"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final candSnap = await _firestore
          .collection('elections').doc(electionId).collection('candidates').get();
      final batch = _firestore.batch();
      for (final d in candSnap.docs) { batch.update(d.reference, {'votes': 0}); }
      final votesSnap = await _firestore
          .collection('elections').doc(electionId).collection('votes').get();
      for (final d in votesSnap.docs) { batch.delete(d.reference); }
      await batch.commit();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Votes reset.'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  // ── Create election ───────────────────────────────────────────────────────
  Future<void> _createElection() async {
    if (!_electionFormKey.currentState!.validate()) return;
    final startsAt = DateTime.tryParse(_electionStartCtrl.text.trim());
    final endsAt = DateTime.tryParse(_electionEndCtrl.text.trim());
    if (startsAt == null || endsAt == null || endsAt.isBefore(startsAt)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Use YYYY-MM-DD and ensure end is after start.')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final positions = _electionPositionsCtrl.text
          .split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
      final docRef = await _firestore.collection('elections').add({
        'title': _electionTitleCtrl.text.trim(),
        'description': _electionDescCtrl.text.trim(),
        'startsAt': Timestamp.fromDate(startsAt),
        'endsAt': Timestamp.fromDate(endsAt),
        'positions': positions,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': _auth.currentUser?.uid,
        'isActive': true,
        'totalVotes': 0,
      });
      await docRef.collection('votes').doc('stats')
          .set({'totalVotes': 0, 'lastUpdated': FieldValue.serverTimestamp()});
      _electionTitleCtrl.clear(); _electionDescCtrl.clear();
      _electionStartCtrl.clear(); _electionEndCtrl.clear();
      _electionPositionsCtrl.clear();
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Election created!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Add candidate ─────────────────────────────────────────────────────────
  Future<void> _addCandidate() async {
    if (!_candidateFormKey.currentState!.validate()) return;
    if (_selectedElectionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select an election.')));
      return;
    }
    if (_selectedPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select a candidate photo.'),
          backgroundColor: Colors.orange));
      return;
    }
    setState(() { _isUploading = true; _uploadProgress = 0; });
    try {
      final String? photoBase64 = await _encodePhotoToBase64();
      if (photoBase64 == null) {
        if (mounted) {
          setState(() { _isUploading = false; _uploadProgress = 0; });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Failed to process photo. Please try again.'),
              backgroundColor: Colors.red));
        }
        return;
      }
      await _firestore.collection('elections').doc(_selectedElectionId)
          .collection('candidates').add({
        'name': _candidateNameCtrl.text.trim(),
        'position': _candidatePositionCtrl.text.trim(),
        'photoBase64': photoBase64,  // Photo file bytes saved as base64 in Firestore
        'bio': _candidateBioCtrl.text.trim(),
        'electionId': _selectedElectionId,
        'votes': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': _auth.currentUser?.uid,
      });
      _candidateNameCtrl.clear(); _candidatePositionCtrl.clear(); _candidateBioCtrl.clear();
      if (mounted) {
        setState(() { _selectedPhoto = null; _isUploading = false; _uploadProgress = 0; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Candidate added successfully!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        setState(() { _isUploading = false; _uploadProgress = 0; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to add candidate: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ── Create admin ──────────────────────────────────────────────────────────
  Future<void> _createAdminAccount() async {
    if (!_adminFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final regQuery = await _firestore.collection('users')
          .where('registrationNumber', isEqualTo: _adminRegCtrl.text.trim())
          .limit(1).get();
      if (regQuery.docs.isNotEmpty) {
        if (mounted) setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registration number already exists.')));
        return;
      }
      final secondaryApp = await firebase_auth.FirebaseAuth.instanceFor(
          app: firebase_auth.FirebaseAuth.instance.app);
      final cred = await secondaryApp.createUserWithEmailAndPassword(
        email: _adminEmailCtrl.text.trim(), password: _adminPasswordCtrl.text);
      await _firestore.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'registrationNumber': _adminRegCtrl.text.trim(),
        'name': _adminNameCtrl.text.trim(),
        'email': _adminEmailCtrl.text.trim(),
        'role': 'admin',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': _auth.currentUser?.uid,
      });
      await cred.user!.updateDisplayName(_adminNameCtrl.text.trim());
      await secondaryApp.signOut();
      _adminNameCtrl.clear(); _adminEmailCtrl.clear();
      _adminRegCtrl.clear(); _adminPasswordCtrl.clear();
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Admin account created!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _auth.signOut();
      if (mounted) Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    }
  }

  // ── Print report ──────────────────────────────────────────────────────────
  Future<void> _printElectionReport(
      String electionTitle, List<Map<String, dynamic>> positions) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) {
          final widgets = <pw.Widget>[
            pw.Text('Election Results Report',
                style: pw.TextStyle(
                    fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(electionTitle,
                style: pw.TextStyle(
                    fontSize: 16, color: PdfColors.blueGrey700)),
            pw.SizedBox(height: 4),
            pw.Text(
                'Generated: ${DateTime.now().toString().substring(0, 16)}',
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey600)),
            pw.Divider(thickness: 1.5),
            pw.SizedBox(height: 8),
          ];

          for (final pos in positions) {
            final posName = pos['position'] as String;
            final candidates =
                pos['candidates'] as List<Map<String, dynamic>>;
            final totalVotes = candidates.fold<int>(
                0, (sum, c) => sum + (c['votes'] as int));

            widgets.add(pw.Text(posName,
                style: pw.TextStyle(
                    fontSize: 14, fontWeight: pw.FontWeight.bold)));
            widgets.add(pw.SizedBox(height: 6));

            // Table header
            widgets.add(pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.blueGrey100),
                  children: [
                    _pdfCell('Candidate', bold: true),
                    _pdfCell('Votes', bold: true),
                    _pdfCell('Percentage', bold: true),
                  ],
                ),
                ...candidates.map((c) {
                  final votes = c['votes'] as int;
                  final pct = totalVotes > 0
                      ? (votes / totalVotes * 100).toStringAsFixed(1)
                      : '0.0';
                  return pw.TableRow(children: [
                    _pdfCell(c['name'] as String),
                    _pdfCell('$votes'),
                    _pdfCell('$pct%'),
                  ]);
                }),
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    _pdfCell('Total', bold: true),
                    _pdfCell('$totalVotes', bold: true),
                    _pdfCell('100%', bold: true),
                  ],
                ),
              ],
            ));
            widgets.add(pw.SizedBox(height: 16));
          }
          return widgets;
        },
      ),
    );

    await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(),
        name: '${electionTitle.replaceAll(' ', '_')}_results.pdf');
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 11,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  // ── Voter report helper ───────────────────────────────────────────────────
  Future<List<VoterReportRow>> _getVoterReport(String electionId) async {
    try {
      final usersSnap = await _firestore.collection('users').get();
      final votesSnap = await _firestore
          .collection('elections').doc(electionId).collection('votes').get();
      final votedIds = votesSnap.docs.map((d) => d.id).toSet();
      return usersSnap.docs.map((d) {
        final data = d.data();
        return VoterReportRow(
          name: data['name'] ?? 'Unknown',
          registrationNumber: data['registrationNumber'] ?? 'N/A',
          status: votedIds.contains(d.id) ? 'Voted' : 'Not Voted',
        );
      }).toList();
    } catch (_) { return []; }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final sections = [
      (icon: Icons.how_to_vote_outlined,      label: 'Elections'),
      (icon: Icons.person_add_outlined,        label: 'Candidates'),
      (icon: Icons.admin_panel_settings_outlined, label: 'Admins'),
      (icon: Icons.bar_chart_outlined,         label: 'Reports'),
      (icon: Icons.people_outlined,            label: 'Users'),
    ];

    final bodies = [
      _buildElectionsTab(),
      _buildCandidatesTab(),
      _buildCreateAdminTab(),
      _buildReportsTab(),
      _buildUsersTab(),
    ];

    return Scaffold(
      backgroundColor: colorScheme.surface,

      // ── Drawer ────────────────────────────────────────────────────────────
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(color: colorScheme.primary),
              accountName: Text(
                widget.currentUser.displayName ?? 'Admin',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              accountEmail: Text(widget.currentUser.email ?? ''),
              currentAccountPicture: CircleAvatar(
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  (widget.currentUser.displayName ?? widget.currentUser.email ?? 'A')[0]
                      .toUpperCase(),
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary),
                ),
              ),
            ),
            ...List.generate(sections.length, (i) {
              final s = sections[i];
              final selected = _selectedIndex == i;
              return ListTile(
                leading: Icon(s.icon,
                    color: selected ? colorScheme.primary : Colors.grey[600]),
                title: Text(s.label,
                    style: TextStyle(
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        color: selected ? colorScheme.primary : null)),
                selected: selected,
                selectedTileColor: colorScheme.primaryContainer.withOpacity(0.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                onTap: () {
                  setState(() => _selectedIndex = i);
                  Navigator.pop(context);
                },
              );
            }),
            const Spacer(),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Logout',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              onTap: _logout,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),

      // ── AppBar ────────────────────────────────────────────────────────────
      appBar: AppBar(
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          sections[_selectedIndex].label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout, color: Colors.white, size: 18),
              label: const Text('Logout', style: TextStyle(color: Colors.white)),
              style: TextButton.styleFrom(
                backgroundColor: Colors.white24,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              ),
            ),
          ),
        ],
      ),

      // ── Body ──────────────────────────────────────────────────────────────
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : bodies[_selectedIndex],
    );
  }

  // ── Elections tab ─────────────────────────────────────────────────────────
  Widget _buildElectionsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Create election form
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _electionFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionHeader(Icons.add_circle_outline, 'Create New Election'),
                  const SizedBox(height: 16),
                  _field(_electionTitleCtrl, 'Election Title', Icons.title),
                  const SizedBox(height: 12),
                  _field(_electionDescCtrl, 'Description', Icons.description, maxLines: 2),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _dateField(_electionStartCtrl, 'Start Date')),
                    const SizedBox(width: 12),
                    Expanded(child: _dateField(_electionEndCtrl, 'End Date')),
                  ]),
                  const SizedBox(height: 12),
                  _field(_electionPositionsCtrl, 'Positions (comma separated)', Icons.list),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _createElection,
                    icon: const Icon(Icons.add),
                    label: const Text('Create Election'),
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Existing elections list with results
        _sectionHeader(Icons.list_alt, 'All Elections & Results'),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('elections')
              .orderBy('createdAt', descending: true).snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final docs = snap.data!.docs;
            if (docs.isEmpty) return const Text('No elections yet.');
            return Column(
              children: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final startsAt = (data['startsAt'] as Timestamp).toDate();
                final endsAt = (data['endsAt'] as Timestamp).toDate();
                final now = DateTime.now();
                final isActive = now.isAfter(startsAt) && now.isBefore(endsAt);
                final isCompleted = now.isAfter(endsAt);
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: isActive
                          ? Colors.green[100]
                          : isCompleted ? Colors.grey[200] : Colors.blue[100],
                      child: Icon(
                        isActive ? Icons.how_to_vote : isCompleted ? Icons.check_circle : Icons.schedule,
                        color: isActive ? Colors.green : isCompleted ? Colors.grey : Colors.blue,
                        size: 20,
                      ),
                    ),
                    title: Text(data['title'] ?? 'Untitled',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      isActive ? 'Active' : isCompleted ? 'Completed' : 'Upcoming',
                      style: TextStyle(
                        color: isActive ? Colors.green : isCompleted ? Colors.grey : Colors.blue,
                        fontSize: 12,
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) {
                        if (value == 'edit') _editElection(doc.id, data);
                        if (value == 'reset') _resetVotes(doc.id, data['title'] ?? '');
                        if (value == 'delete') _deleteElection(doc.id, data['title'] ?? '');
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'edit',
                            child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Edit')])),
                        const PopupMenuItem(value: 'reset',
                            child: Row(children: [Icon(Icons.refresh, size: 18, color: Colors.orange), SizedBox(width: 8), Text('Reset Votes', style: TextStyle(color: Colors.orange))])),
                        const PopupMenuItem(value: 'delete',
                            child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                      ],
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: StreamBuilder<QuerySnapshot>(
                          stream: _firestore.collection('elections')
                              .doc(doc.id).collection('candidates').snapshots(),
                          builder: (context, candSnap) {
                            if (!candSnap.hasData) return const LinearProgressIndicator();
                            final candidates = candSnap.data!.docs;
                            if (candidates.isEmpty) {
                              return const Text('No candidates added yet.',
                                  style: TextStyle(color: Colors.grey));
                            }
                            // Group by position
                            final Map<String, List<QueryDocumentSnapshot>> byPos = {};
                            for (final c in candidates) {
                              final cd = c.data() as Map<String, dynamic>;
                              final pos = cd['position'] ?? 'Unknown';
                              byPos.putIfAbsent(pos, () => []).add(c);
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: byPos.entries.map((entry) {
                                final totalVotes = entry.value.fold<int>(0, (s, c) {
                                  final cd = c.data() as Map<String, dynamic>;
                                  return s + ((cd['votes'] as int?) ?? 0);
                                });
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(entry.key,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold, fontSize: 13)),
                                    const SizedBox(height: 6),
                                    ...entry.value.map((c) {
                                      final cd = c.data() as Map<String, dynamic>;
                                      final votes = (cd['votes'] as int?) ?? 0;
                                      final pct = totalVotes > 0
                                          ? votes / totalVotes : 0.0;
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(cd['name'] ?? '',
                                                    style: const TextStyle(fontSize: 13)),
                                                Text('$votes votes  '
                                                    '(${(pct * 100).toStringAsFixed(1)}%)',
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600)),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(4),
                                              child: LinearProgressIndicator(
                                                value: pct,
                                                minHeight: 8,
                                                backgroundColor: Colors.grey[200],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                    const Divider(),
                                  ],
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  // ── Candidates tab ────────────────────────────────────────────────────────
  Widget _buildCandidatesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Add candidate form
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionHeader(Icons.person_add_alt_1, 'Add Candidate'),
                const SizedBox(height: 16),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('elections')
                      .orderBy('createdAt', descending: true).snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const LinearProgressIndicator();
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) return const Text('No elections yet. Create one first.');
                    return DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Select Election',
                        prefixIcon: const Icon(Icons.how_to_vote_outlined),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      value: _selectedElectionId,
                      items: docs.map((d) {
                        final data = d.data() as Map<String, dynamic>;
                        return DropdownMenuItem(
                            value: d.id, child: Text(data['title'] ?? 'Untitled'));
                      }).toList(),
                      onChanged: (v) => setState(() => _selectedElectionId = v),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Form(
                  key: _candidateFormKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _field(_candidateNameCtrl, 'Candidate Name', Icons.person_outline),
                      const SizedBox(height: 12),
                      _field(_candidatePositionCtrl, 'Position', Icons.work_outline),
                      const SizedBox(height: 12),
                      // Photo picker
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          children: [
                            const Text('Candidate Photo',
                                style: TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: _showPhotoPicker,
                              child: CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.grey[200],
                                backgroundImage: _selectedPhoto != null
                                    ? NetworkImage(_selectedPhoto!.path)
                                    : null,
                                child: _selectedPhoto == null
                                    ? const Icon(Icons.add_a_photo, size: 32, color: Colors.grey)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _showPhotoPicker,
                                  icon: const Icon(Icons.photo_camera, size: 16),
                                  label: Text(_selectedPhoto == null ? 'Add Photo' : 'Change Photo'),
                                ),
                                if (_selectedPhoto != null) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () => setState(() => _selectedPhoto = null),
                                  ),
                                ],
                              ],
                            ),
                            if (_isUploading && _uploadProgress > 0) ...[
                              const SizedBox(height: 8),
                              LinearProgressIndicator(value: _uploadProgress),
                              Text('${(_uploadProgress * 100).toStringAsFixed(0)}% uploaded',
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _field(_candidateBioCtrl, 'Bio / Manifesto', Icons.notes, maxLines: 3),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: (_isUploading || _isLoading) ? null : _addCandidate,
                        icon: _isUploading
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.person_add),
                        label: Text(_isUploading ? 'Uploading...' : 'Add Candidate'),
                        style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Existing candidates list from database
        _sectionHeader(Icons.people, 'All Candidates'),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('elections').snapshots(),
          builder: (context, elecSnap) {
            if (!elecSnap.hasData) return const Center(child: CircularProgressIndicator());
            final elections = elecSnap.data!.docs;
            if (elections.isEmpty) return const Text('No elections yet.');
            return Column(
              children: elections.map((elecDoc) {
                final elecData = elecDoc.data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ExpansionTile(
                    title: Text(elecData['title'] ?? 'Untitled',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    leading: const Icon(Icons.how_to_vote_outlined),
                    children: [
                      StreamBuilder<QuerySnapshot>(
                        stream: _firestore.collection('elections')
                            .doc(elecDoc.id).collection('candidates')
                            .orderBy('position').snapshots(),
                        builder: (context, candSnap) {
                          if (!candSnap.hasData) return const LinearProgressIndicator();
                          final candidates = candSnap.data!.docs;
                          if (candidates.isEmpty) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No candidates yet.',
                                  style: TextStyle(color: Colors.grey)),
                            );
                          }
                          return Column(
                            children: candidates.map((c) {
                              final cd = c.data() as Map<String, dynamic>;
                              return ListTile(
                                leading: _candidatePhoto(cd, radius: 20),
                                title: Text(cd['name'] ?? ''),
                                subtitle: Text(cd['position'] ?? ''),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${cd['votes'] ?? 0} votes',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert, size: 18),
                                      onSelected: (v) {
                                        if (v == 'edit') _editCandidate(elecDoc.id, c.id, cd);
                                        if (v == 'delete') _deleteCandidate(elecDoc.id, c.id, cd['name'] ?? '');
                                      },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(value: 'edit',
                                            child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Edit')])),
                                        const PopupMenuItem(value: 'delete',
                                            child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  // ── Create admin tab ──────────────────────────────────────────────────────
  Widget _buildCreateAdminTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _adminFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionHeader(Icons.admin_panel_settings, 'Create Admin Account'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber[200]!),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Admin accounts have full access to manage elections, candidates, and reports.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                _field(_adminNameCtrl, 'Full Name', Icons.person_outline,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null),
                const SizedBox(height: 12),
                _field(_adminRegCtrl, 'Admin ID', Icons.badge_outlined,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter an ID' : null),
                const SizedBox(height: 12),
                _field(_adminEmailCtrl, 'Email Address', Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Enter an email';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    }),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adminPasswordCtrl,
                  obscureText: _obscureAdminPassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureAdminPassword
                          ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _obscureAdminPassword = !_obscureAdminPassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter a password';
                    if (v.length < 6) return 'At least 6 characters required';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _createAdminAccount,
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('Create Admin Account'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Reports tab ───────────────────────────────────────────────────────────
  Widget _buildReportsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('elections').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final elections = snap.data!.docs;
        if (elections.isEmpty) return const Center(child: Text('No elections yet.'));
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: elections.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final doc = elections[i];
            final data = doc.data() as Map<String, dynamic>;
            return Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Election header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(data['title'] ?? 'Untitled',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer)),
                        ),
                        // Print button
                        StreamBuilder<QuerySnapshot>(
                          stream: _firestore.collection('elections')
                              .doc(doc.id).collection('candidates').snapshots(),
                          builder: (context, candSnap) {
                            return IconButton(
                              icon: const Icon(Icons.print_outlined),
                              tooltip: 'Print Results',
                              color: Theme.of(context).colorScheme.primary,
                              onPressed: !candSnap.hasData ? null : () async {
                                final candidates = candSnap.data!.docs;
                                final Map<String, List<Map<String, dynamic>>> byPos = {};
                                for (final c in candidates) {
                                  final cd = c.data() as Map<String, dynamic>;
                                  final pos = cd['position'] ?? 'Unknown';
                                  byPos.putIfAbsent(pos, () => []).add({
                                    'name': cd['name'] ?? '',
                                    'votes': (cd['votes'] as int?) ?? 0,
                                  });
                                }
                                final positions = byPos.entries.map((e) => {
                                  'position': e.key,
                                  'candidates': e.value,
                                }).toList();
                                await _printElectionReport(
                                    data['title'] ?? 'Election', positions);
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  // Candidate results per position with bar chart
                  StreamBuilder<QuerySnapshot>(
                    stream: _firestore.collection('elections')
                        .doc(doc.id).collection('candidates').snapshots(),
                    builder: (context, candSnap) {
                      if (!candSnap.hasData) return const LinearProgressIndicator();
                      final candidates = candSnap.data!.docs;
                      if (candidates.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('No candidates yet.',
                              style: TextStyle(color: Colors.grey)),
                        );
                      }
                      final Map<String, List<QueryDocumentSnapshot>> byPos = {};
                      for (final c in candidates) {
                        final cd = c.data() as Map<String, dynamic>;
                        byPos.putIfAbsent(cd['position'] ?? 'Unknown', () => []).add(c);
                      }
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: byPos.entries.map((entry) {
                            final list = entry.value;
                            final totalVotes = list.fold<int>(0, (s, c) {
                              final cd = c.data() as Map<String, dynamic>;
                              return s + ((cd['votes'] as int?) ?? 0);
                            });
                            final barColors = [
                              const Color(0xFF2196F3), const Color(0xFF4CAF50),
                              const Color(0xFFFF9800), const Color(0xFF9C27B0),
                              const Color(0xFFF44336), const Color(0xFF00BCD4),
                            ];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(Icons.work_outline, size: 16, color: Colors.blueGrey),
                                  const SizedBox(width: 6),
                                  Text(entry.key,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  const Spacer(),
                                  Text('Total: $totalVotes votes',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                ]),
                                const SizedBox(height: 12),
                                // Bar chart
                                SizedBox(
                                  height: 180,
                                  child: BarChart(
                                    BarChartData(
                                      maxY: (list.fold<int>(0, (m, c) {
                                        final cd = c.data() as Map<String, dynamic>;
                                        final v = (cd['votes'] as int?) ?? 0;
                                        return v > m ? v : m;
                                      }) + 1).toDouble(),
                                      barTouchData: BarTouchData(
                                        touchTooltipData: BarTouchTooltipData(
                                          getTooltipItem: (group, gi, rod, ri) {
                                            final cd = list[gi].data() as Map<String, dynamic>;
                                            final votes = (cd['votes'] as int?) ?? 0;
                                            final pct = totalVotes > 0
                                                ? (votes / totalVotes * 100).toStringAsFixed(1) : '0.0';
                                            return BarTooltipItem(
                                              '${cd['name']}\n$votes ($pct%)',
                                              const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                            );
                                          },
                                        ),
                                      ),
                                      titlesData: FlTitlesData(
                                        leftTitles: AxisTitles(sideTitles: SideTitles(
                                          showTitles: true, reservedSize: 28,
                                          getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                                              style: const TextStyle(fontSize: 10)),
                                        )),
                                        bottomTitles: AxisTitles(sideTitles: SideTitles(
                                          showTitles: true, reservedSize: 32,
                                          getTitlesWidget: (value, _) {
                                            final idx = value.toInt();
                                            if (idx < 0 || idx >= list.length) return const SizedBox.shrink();
                                            final cd = list[idx].data() as Map<String, dynamic>;
                                            final name = (cd['name'] as String? ?? '');
                                            final short = name.length > 7 ? '${name.substring(0, 6)}…' : name;
                                            return Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(short, style: const TextStyle(fontSize: 9), textAlign: TextAlign.center),
                                            );
                                          },
                                        )),
                                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      ),
                                      gridData: FlGridData(
                                        drawVerticalLine: false,
                                        getDrawingHorizontalLine: (_) => FlLine(color: Colors.grey[200]!, strokeWidth: 1),
                                      ),
                                      borderData: FlBorderData(show: false),
                                      barGroups: List.generate(list.length, (i) {
                                        final cd = list[i].data() as Map<String, dynamic>;
                                        final votes = (cd['votes'] as int?) ?? 0;
                                        return BarChartGroupData(x: i, barRods: [
                                          BarChartRodData(
                                            toY: votes.toDouble(),
                                            color: barColors[i % barColors.length],
                                            width: 24,
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                                          ),
                                        ]);
                                      }),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                // List below chart
                                ...List.generate(list.length, (i) {
                                  final cd = list[i].data() as Map<String, dynamic>;
                                  final votes = (cd['votes'] as int?) ?? 0;
                                  final pct = totalVotes > 0 ? votes / totalVotes : 0.0;
                                  final color = barColors[i % barColors.length];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(children: [
                                      _candidatePhoto(cd, radius: 14),
                                      const SizedBox(width: 8),
                                      Expanded(child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                            Text(cd['name'] ?? '', style: const TextStyle(fontSize: 13)),
                                            Text('$votes  (${(pct * 100).toStringAsFixed(1)}%)',
                                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                                          ]),
                                          const SizedBox(height: 3),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: pct, minHeight: 7,
                                              backgroundColor: Colors.grey[200], color: color,
                                            ),
                                          ),
                                        ],
                                      )),
                                    ]),
                                  );
                                }),
                                const Divider(height: 20),
                              ],
                            );
                          }).toList(),
                        ),
                      );
                    },
                  ),
                  // Voter turnout
                  FutureBuilder<List<VoterReportRow>>(
                    future: _getVoterReport(doc.id),
                    builder: (context, reportSnap) {
                      if (!reportSnap.hasData) return const SizedBox.shrink();
                      final report = reportSnap.data!;
                      final voted = report.where((r) => r.status == 'Voted').length;
                      final total = report.length;
                      final turnout = total > 0 ? voted / total : 0.0;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Voter Turnout',
                                      style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text('$voted / $total  (${(turnout * 100).toStringAsFixed(1)}%)',
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: turnout,
                                  minHeight: 8,
                                  backgroundColor: Colors.green[100],
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Resolve storage path to a displayable image ──────────────────────────
  Widget _candidatePhoto(Map<String, dynamic> cd, {double radius = 20}) {
    // Priority: base64 bytes → storage path → direct URL
    final base64Str = cd['photoBase64'] as String?;
    final path = cd['photoPath'] as String?;
    final url = cd['photoUrl'] as String?;

    // New format: base64 bytes stored directly in Firestore
    if (base64Str != null && base64Str.isNotEmpty) {
      try {
        final bytes = base64Decode(base64Str);
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {}
    }

    // Legacy: storage path
    if (path != null && path.isNotEmpty) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instanceFor(
                bucket: 'gs://bsuvotingapp.firebasestorage.app')
            .ref()
            .child(path)
            .getDownloadURL(),
        builder: (context, snap) {
          if (snap.hasData) {
            return CircleAvatar(
              radius: radius,
              backgroundImage: NetworkImage(snap.data!),
            );
          }
          return CircleAvatar(
            radius: radius,
            backgroundColor: Colors.grey[200],
            child: snap.hasError
                ? const Icon(Icons.broken_image, size: 16, color: Colors.grey)
                : SizedBox(
                    width: radius * 0.7, height: radius * 0.7,
                    child: const CircularProgressIndicator(strokeWidth: 2)),
          );
        },
      );
    }

    // Legacy: direct URL
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(url),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.grey[200],
      child: Icon(Icons.person, size: radius * 0.9, color: Colors.grey),
    );
  }

  // ── Users tab ─────────────────────────────────────────────────────────────
  Widget _buildUsersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('users').orderBy('name').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final users = snap.data!.docs;
        if (users.isEmpty) return const Center(child: Text('No users yet.'));

        final students = users.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['role'] != 'admin';
        }).toList();
        final admins = users.where((d) {
          final data = d.data() as Map<String, dynamic>;
          return data['role'] == 'admin';
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Summary chips
            Row(children: [
              _statChip(Icons.people, '${students.length} Students', Colors.blue),
              const SizedBox(width: 10),
              _statChip(Icons.admin_panel_settings, '${admins.length} Admins', Colors.purple),
            ]),
            const SizedBox(height: 20),

            // Students
            _sectionHeader(Icons.school_outlined, 'Students'),
            const SizedBox(height: 10),
            if (students.isEmpty)
              const Text('No students registered yet.',
                  style: TextStyle(color: Colors.grey))
            else
              ...students.map((doc) => _userCard(doc)),

            const SizedBox(height: 20),

            // Admins
            _sectionHeader(Icons.admin_panel_settings_outlined, 'Admins'),
            const SizedBox(height: 10),
            if (admins.isEmpty)
              const Text('No admins yet.', style: TextStyle(color: Colors.grey))
            else
              ...admins.map((doc) => _userCard(doc, isAdmin: true)),
          ],
        );
      },
    );
  }

  Widget _statChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w600, fontSize: 13)),
      ]),
    );
  }

  Widget _userCard(QueryDocumentSnapshot doc, {bool isAdmin = false}) {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['name'] ?? 'Unknown';
    final email = data['email'] ?? '';
    final regNo = data['registrationNumber'] ?? '';
    final role = data['role'] ?? 'student';
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: isAdmin
              ? Colors.purple[100]
              : colorScheme.primaryContainer,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isAdmin ? Colors.purple : colorScheme.primary),
          ),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email, style: const TextStyle(fontSize: 12)),
            if (regNo.isNotEmpty)
              Text('ID: $regNo',
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            if (value == 'edit') _editUser(doc.id, data);
            if (value == 'delete') _deleteUser(doc.id, name, role);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(children: [
                Icon(Icons.edit_outlined, size: 18),
                SizedBox(width: 8),
                Text('Edit'),
              ]),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline, size: 18, color: Colors.red),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: Colors.red)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ── Edit user ─────────────────────────────────────────────────────────────
  Future<void> _editUser(String uid, Map<String, dynamic> data) async {
    final nameCtrl = TextEditingController(text: data['name'] ?? '');
    final regCtrl =
        TextEditingController(text: data['registrationNumber'] ?? '');
    String role = data['role'] ?? 'student';
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Edit User'),
          content: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline)),
                validator: (v) =>
                    v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: regCtrl,
                decoration: const InputDecoration(
                    labelText: 'Registration / Admin ID',
                    prefixIcon: Icon(Icons.badge_outlined)),
                validator: (v) =>
                    v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: role,
                decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.manage_accounts_outlined)),
                items: const [
                  DropdownMenuItem(value: 'student', child: Text('Student')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (v) => setDialogState(() => role = v!),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                await _firestore.collection('users').doc(uid).update({
                  'name': nameCtrl.text.trim(),
                  'registrationNumber': regCtrl.text.trim(),
                  'role': role,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    regCtrl.dispose();
  }

  // ── Delete user ───────────────────────────────────────────────────────────
  Future<void> _deleteUser(String uid, String name, String role) async {
    // Prevent deleting yourself
    if (uid == _auth.currentUser?.uid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('You cannot delete your own account.'),
          backgroundColor: Colors.orange));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber, color: Colors.red),
          SizedBox(width: 8),
          Text('Delete User'),
        ]),
        content: Text(
            'Delete "$name"?\n\nThis removes their Firestore record. Their Firebase Auth account will remain unless deleted manually from the Firebase Console.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _firestore.collection('users').doc(uid).delete();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('User deleted.'),
              backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  // ── Shared helpers ────────────────────────────────────────────────────────
  Widget _sectionHeader(IconData icon, String title) {
    return Row(children: [
      Icon(icon, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 8),
      Text(title,
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary)),
    ]);
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon,
      {int maxLines = 1,
      TextInputType? keyboardType,
      String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      validator: validator ?? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
    );
  }

  Widget _dateField(TextEditingController ctrl, String label) {
    return TextFormField(
      controller: ctrl,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) {
          ctrl.text =
              '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
        }
      },
      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
    );
  }
}

// ── VoterReportRow ────────────────────────────────────────────────────────
class VoterReportRow {
  final String name;
  final String registrationNumber;
  final String status;
  VoterReportRow({
    required this.name,
    required this.registrationNumber,
    required this.status,
  });
}
