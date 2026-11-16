import 'auth_service.dart';
import 'firebase_api.dart';
import 'spark_provisioning.dart';

class Department {
  final String id;
  final String name;
  final bool managed;

  const Department(this.id, this.name, {required this.managed});
}

class DepartmentService {
  List<String> _path(String dept) => ['departments', dept];

  Department _department(String id, dynamic data) {
    final name = data is Map ? data['name'] : null;
    return Department(
      id,
      id == 'icbs'
          ? 'Mathematics'
          : name is String && name.trim().isNotEmpty
              ? name
              : id.toUpperCase(),
      managed: RegExp(r'^dept[1-9][0-9]{0,11}$').hasMatch(id),
    );
  }

  Future<List<Department>> getDepartments() async {
    final data = await FirebaseApi.database(['departments']);
    return [
      if (data case final Map entries)
        for (final entry in entries.entries)
          if (entry.value is Map && entry.value['deleted'] != true)
            _department(entry.key as String, entry.value),
    ];
  }

  Future<Department> getAssignedDepartment(String id) async {
    final data = await FirebaseApi.database(_path(id));
    if (data is! Map || data['deleted'] == true) {
      throw const FirebaseApiException('Assigned department was not found.');
    }
    return _department(id, data);
  }

  Future<Department> createDepartment(String name) async {
    final id = await SparkProvisioning.createDepartment(name);
    return Department(id, name.trim(), managed: true);
  }

  Future<void> renameDepartment(String id, String name) async {
    await SparkProvisioning.renameDepartment(id, name);
  }

  Future<void> deleteDepartment(String id, String password) async {
    if (!RegExp(r'^dept[1-9][0-9]{0,11}$').hasMatch(id)) {
      throw const FirebaseApiException('This department is protected.');
    }
    final fresh = await AuthService.windows.confirmPassword(
      await FirebaseApi.token(),
      password,
    );
    await FirebaseApi.database(
      ['departments', id],
      method: 'PUT',
      body: {'deleted': true},
      confirmedToken: fresh,
    );
  }

  Future<void> createSecretary(String id, String email, String password) async {
    await SparkProvisioning.createSecretary(id, email, password);
  }

  Future<void> triggerManualRing(String dept, {bool managed = false}) async {
    await FirebaseApi.database([..._path(dept), 'manualRing'],
        method: 'PUT', body: true);
  }

  Future<String> getMode(String dept, {bool managed = false}) async {
    final mode = await FirebaseApi.database([..._path(dept), 'mode']);
    if (mode is! String) {
      throw const FirebaseApiException('Department mode is missing.');
    }
    return mode;
  }

  Future<void> setMode(String dept, String mode, {bool managed = false}) async {
    await FirebaseApi.database([..._path(dept), 'mode'],
        method: 'PUT', body: mode);
  }

  List<String> _schedule(String dept, String mode, bool managed) =>
      [..._path(dept), 'schedules', mode, 'times'];

  Future<List<int>> getSchedule(String dept, String mode,
      {bool managed = false}) async {
    final times = await FirebaseApi.database(_schedule(dept, mode, managed));
    return _decodeTimes(times);
  }

  List<int> _decodeTimes(dynamic times) {
    if (times == null) return [];
    if (times is! List ||
        times.any((time) => time is! int || time < 0 || time >= 1440)) {
      throw const FirebaseApiException(
          'This schedule contains an invalid bell time. Contact your administrator.');
    }
    return times.cast<int>().toSet().toList()..sort();
  }

  Future<void> addTime(String dept, String mode, int minutes,
      {bool managed = false}) async {
    await FirebaseApi.updateSchedule(_schedule(dept, mode, managed), (data) {
      final times = _decodeTimes(data);
      if (!times.contains(minutes)) times.add(minutes);
      return times..sort();
    });
  }

  Future<void> deleteTime(String dept, String mode, int minutes,
      {bool managed = false}) async {
    await FirebaseApi.updateSchedule(_schedule(dept, mode, managed), (data) {
      final times = _decodeTimes(data)..remove(minutes);
      return times.isEmpty ? null : times;
    });
  }
}
