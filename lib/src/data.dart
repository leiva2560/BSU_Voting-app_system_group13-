import 'models.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AppData {
  AppData._();

  static final AppData instance = AppData._();

  // These are now mostly for local cache/offline support
  final List<User> users = [];
  final List<Election> elections = [];
  final List<Candidate> candidates = [];

  FirebaseFirestore? _firestore;
  bool _firestoreReady = false;

  /// Initialize AppData by loading from Firestore if available
  Future<void> initialize() async {
    _firestore = FirebaseFirestore.instance;
    try {
      await _loadFromFirestore();
      _firestoreReady = true;
    } catch (e) {
      // If Firestore isn't available, use sample data
      if (users.isEmpty && elections.isEmpty && candidates.isEmpty) {
        _initSampleData();
      }
      _firestoreReady = false;
    }
  }

  Future<void> _loadFromFirestore() async {
    if (_firestore == null) return;

    // Load users
    final usersSnap = await _firestore!.collection('users').get();
    users.clear();
    for (final doc in usersSnap.docs) {
      final data = doc.data();
      users.add(User(
        registrationNumber: data['registrationNumber'] ?? doc.id,
        name: data['name'] ?? '',
        email: data['email'] ?? '',
        password: data['password'] ?? '',
        isAdmin: data['role'] == 'admin',
        votesByElection: Map<String, Map<String, String>>.from(
          (data['votesByElection'] as Map? ?? {}).map(
            (k, v) => MapEntry(k.toString(), Map<String, String>.from(v as Map)),
          ),
        ),
      ));
    }

    // Load elections with candidates
    final electionsSnap = await _firestore!.collection('elections').get();
    elections.clear();
    candidates.clear();

    for (final doc in electionsSnap.docs) {
      final data = doc.data();
      final startsAt = (data['startsAt'] as Timestamp).toDate();
      final endsAt = (data['endsAt'] as Timestamp).toDate();

      // Load candidates for this election
      final candidatesSnap = await doc.reference.collection('candidates').get();
      final electionCandidates = <Candidate>[];
      for (final candidateDoc in candidatesSnap.docs) {
        final candidateData = candidateDoc.data();
        final candidate = Candidate(
          id: candidateDoc.id,
          name: candidateData['name'] ?? '',
          position: candidateData['position'] ?? '',
          photoUrl: candidateData['photoUrl'] ?? '',
          bio: candidateData['bio'] ?? '',
          electionId: doc.id,
          votes: candidateData['votes'] ?? 0,
        );
        electionCandidates.add(candidate);
        candidates.add(candidate);
      }

      elections.add(Election(
        id: doc.id,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        startsAt: startsAt,
        endsAt: endsAt,
        positions: List<String>.from(data['positions'] ?? []),
        candidates: electionCandidates,
      ));
    }
  }

  User? authenticate(String registrationNumber) {
    final normalized = registrationNumber.trim();
    try {
      return users.firstWhere((user) => user.registrationNumber == normalized);
    } catch (_) {
      return null;
    }
  }

  User? login(String registrationNumber, String password) {
    final user = authenticate(registrationNumber.trim());
    if (user == null) return null;
    if (user.password == password) return user;
    return null;
  }

  Future<User?> signInWithGoogle() async {
    try {
      final google = GoogleSignIn();
      final googleAccount = await google.signIn();
      if (googleAccount == null) return null;

      final googleAuth = await googleAccount.authentication;
      final credential = fb_auth.GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);
      final fbUser = userCredential.user;
      if (fbUser == null || fbUser.email == null) return null;

      // Check if user exists in Firestore; create as admin if new
      final email = fbUser.email!.trim();
      final userDoc = await _firestore!.collection('users').doc(fbUser.uid).get();

      if (!userDoc.exists) {
        await _firestore!.collection('users').doc(fbUser.uid).set({
          'uid': fbUser.uid,
          'registrationNumber': 'ADMIN',
          'name': fbUser.displayName ?? email.split('@').first,
          'email': email,
          'role': 'admin',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Return a local User object for compatibility
      try {
        return users.firstWhere((u) => u.email.toLowerCase() == email.toLowerCase());
      } catch (_) {
        final newUser = User(
          registrationNumber: 'ADMIN',
          name: fbUser.displayName ?? email.split('@').first,
          email: email,
          password: '',
          isAdmin: true,
        );
        users.add(newUser);
        return newUser;
      }
    } catch (e) {
      return null;
    }
  }

  User registerUser(String registrationNumber, String name, String email, String password) {
    final normalized = registrationNumber.trim();
    final existing = authenticate(normalized);
    if (existing != null) return existing;

    final user = User(
      registrationNumber: normalized,
      name: name.trim(),
      email: email.trim(),
      password: password,
    );
    users.add(user);
    return user;
  }

  Election? electionById(String id) {
    try {
      return elections.firstWhere((election) => election.id == id);
    } catch (_) {
      return null;
    }
  }

  Candidate? candidateById(String id) {
    try {
      return candidates.firstWhere((candidate) => candidate.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Candidate> candidatesForElection(String electionId) {
    return candidates.where((c) => c.electionId == electionId).toList();
  }

  Map<String, List<Candidate>> candidatesByPosition(String electionId) {
    final result = <String, List<Candidate>>{};
    for (final candidate in candidatesForElection(electionId)) {
      result.putIfAbsent(candidate.position, () => []).add(candidate);
    }
    return result;
  }

  bool vote(User user, Election election, Map<String, String> selectionByPosition) {
    if (user.hasVotedInElection(election.id)) return false;
    
    for (final candidateId in selectionByPosition.values) {
      final candidate = candidateById(candidateId);
      if (candidate != null) {
        candidate.votes += 1;
      }
    }
    user.votesByElection[election.id] = Map.from(selectionByPosition);
    return true;
  }

  bool hasUserVotedInElection(User user, Election election) {
    return user.hasVotedInElection(election.id);
  }

  // Helper properties using DateTime comparison
  List<Election> get activeElections {
    final now = DateTime.now();
    return elections.where((e) => e.startsAt.isBefore(now) && e.endsAt.isAfter(now)).toList();
  }

  List<Election> get upcomingElections {
    final now = DateTime.now();
    return elections.where((e) => e.startsAt.isAfter(now)).toList();
  }

  List<Election> get completedElections {
    final now = DateTime.now();
    return elections.where((e) => e.endsAt.isBefore(now)).toList();
  }

  List<VoterReportRow> voterReport(String electionId) {
    return users.map((user) {
      final voted = user.hasVotedInElection(electionId);
      return VoterReportRow(
        registrationNumber: user.registrationNumber,
        name: user.name,
        status: voted ? 'Voted' : 'Pending',
        electionId: electionId,
      );
    }).toList();
  }

  void _initSampleData() {
    users.addAll([
      User(registrationNumber: '0000', name: 'Admin User', email: 'admin@school.edu', password: 'adminpass', isAdmin: true),
      User(registrationNumber: '1001', name: 'Amina Doe', email: 'amina@example.edu', password: 'password1'),
      User(registrationNumber: '1002', name: 'Daniel Kim', email: 'daniel@example.edu', password: 'password2'),
    ]);

    final now = DateTime.now();
    final activeElection = Election(
      id: 'election-1',
      title: 'Guild President 2026',
      description: 'Secure voting for the 2026 Guild President leadership team.',
      startsAt: now.subtract(const Duration(days: 1)),
      endsAt: now.add(const Duration(days: 1)),
      positions: ['President', 'Treasurer', 'Secretary'],
      candidates: [],
    );

    final upcomingElection = Election(
      id: 'election-2',
      title: 'GRC 2026',
      description: 'Upcoming student election for the GRC.',
      startsAt: now.add(const Duration(days: 2)),
      endsAt: now.add(const Duration(days: 5)),
      positions: ['Chair', 'Events Lead'],
      candidates: [],
    );

    final completedElection = Election(
      id: 'election-3',
      title: 'Ministers 2026',
      description: 'Closed election results for the ministers office.',
      startsAt: now.subtract(const Duration(days: 20)),
      endsAt: now.subtract(const Duration(days: 10)),
      positions: ['Captain', 'Secretary'],
      candidates: [],
    );

    elections.addAll([activeElection, upcomingElection, completedElection]);

    candidates.addAll([
      Candidate(
        id: 'candidate-1',
        name: 'Imani A.',
        position: 'President',
        photoUrl: 'https://picsum.photos/seed/1/200/200',
        bio: 'Focused on transparency, student safety, and digital access.',
        electionId: activeElection.id,
      ),
      Candidate(
        id: 'candidate-2',
        name: 'Chris B.',
        position: 'President',
        photoUrl: 'https://picsum.photos/seed/2/200/200',
        bio: 'Committed to inclusive budgeting and campus outreach.',
        electionId: activeElection.id,
      ),
      Candidate(
        id: 'candidate-3',
        name: 'Sara J.',
        position: 'Treasurer',
        photoUrl: 'https://picsum.photos/seed/3/200/200',
        bio: 'Experienced in financial planning and accountability.',
        electionId: activeElection.id,
      ),
    ]);
  }
}

// Helper class for voter report
class VoterReportRow {
  final String registrationNumber;
  final String name;
  final String status;
  final String electionId;

  VoterReportRow({
    required this.registrationNumber,
    required this.name,
    required this.status,
    required this.electionId,
  });
}