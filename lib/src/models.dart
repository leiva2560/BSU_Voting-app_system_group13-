class User {
  User({
    required this.registrationNumber,
    required this.name,
    required this.email,
    required this.password,
    this.isAdmin = false,
    Map<String, Map<String, String>>? votesByElection,
  }) : votesByElection = votesByElection ?? {};

  final String registrationNumber;
  String name;
  String email;
  String password;
  bool isAdmin;
  final Map<String, Map<String, String>> votesByElection;

  bool hasVotedInElection(String electionId) {
    return votesByElection.containsKey(electionId);
  }
}

class Candidate {
  final String id;
  String name;
  String position;
  String photoUrl;
  String bio;
  final String electionId;
  int votes;

  Candidate({
    required this.id,
    required this.name,
    required this.position,
    required this.photoUrl,
    required this.bio,
    required this.electionId,
    this.votes = 0,
  });
}

class Election {
  final String id;
  final String title;
  final String description;
  final DateTime startsAt;
  final DateTime endsAt;
  final List<String> positions;
  final List<Candidate> candidates;

  Election({
    required this.id,
    required this.title,
    required this.description,
    required this.startsAt,
    required this.endsAt,
    required this.positions,
    required this.candidates,
  });

  bool get isActive {
    final now = DateTime.now();
    return now.isAfter(startsAt) && now.isBefore(endsAt);
  }

  bool get isUpcoming {
    return DateTime.now().isBefore(startsAt);
  }

  bool get isCompleted {
    return DateTime.now().isAfter(endsAt);
  }
}