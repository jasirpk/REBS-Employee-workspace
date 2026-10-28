
class Employee {
  final String id;
  final String name;
  final String department;
  final String timezone;
  final double officeLatitude;
  final double officeLongitude;
  final int officeRadiusMeters;

  const Employee({
    required this.id,
    required this.name,
    required this.department,
    required this.timezone,
    required this.officeLatitude,
    required this.officeLongitude,
    required this.officeRadiusMeters,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    final office = json['office'] as Map<String, dynamic>;

    return Employee(
      id: json['id'] as String,
      name: json['name'] as String,
      department: json['department'] as String,
      timezone: json['timezone'] as String,
      officeLatitude: (office['latitude'] as num).toDouble(),
      officeLongitude: (office['longitude'] as num).toDouble(),
      officeRadiusMeters: office['radiusMeters'] as int,
    );
  }
}
