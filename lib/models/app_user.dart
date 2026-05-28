class AppUser {
  final String uid;
  final String registrationNumber;
  final String name;
  final String email;
  final bool isAdmin;

  AppUser({
    required this.uid,
    required this.registrationNumber,
    required this.name,
    required this.email,
    this.isAdmin = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'registrationNumber': registrationNumber,
      'name': name,
      'email': email,
      'isAdmin': isAdmin,
    };
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      registrationNumber: map['registrationNumber'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      isAdmin: map['role'] == 'admin',
    );
  }
}