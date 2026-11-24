/// The profile attributes returned by UAE PASS for the approved scope.
///
/// Attributes vary by account type and integration.
final class UaepassUser {
  final String? sub;
  final String? fullnameAR;
  final String? gender;
  final String? mobile;
  final String? lastnameEN;
  final String? fullnameEN;
  final String? uuid;
  final String? lastnameAR;
  final String? idn;
  final String? nationalityEN;
  final String? firstnameEN;
  final String? userType;
  final String? nationalityAR;
  final String? firstnameAR;
  final String? email;

  const UaepassUser({
    this.sub,
    this.fullnameAR,
    this.gender,
    this.mobile,
    this.lastnameEN,
    this.fullnameEN,
    this.uuid,
    this.lastnameAR,
    this.idn,
    this.nationalityEN,
    this.firstnameEN,
    this.userType,
    this.nationalityAR,
    this.firstnameAR,
    this.email,
  });

  /// Parses a UAE PASS user information response.
  UaepassUser.fromJson(Map<String, Object?> json)
    : sub = json['sub'] as String?,
      fullnameAR = json['fullnameAR'] as String?,
      gender = json['gender'] as String?,
      mobile = json['mobile'] as String?,
      lastnameEN = json['lastnameEN'] as String?,
      fullnameEN = json['fullnameEN'] as String?,
      uuid = json['uuid'] as String?,
      lastnameAR = json['lastnameAR'] as String?,
      idn = json['idn'] as String?,
      nationalityEN = json['nationalityEN'] as String?,
      firstnameEN = json['firstnameEN'] as String?,
      userType = json['userType'] as String?,
      nationalityAR = json['nationalityAR'] as String?,
      firstnameAR = json['firstnameAR'] as String?,
      email = json['email'] as String?;
}
