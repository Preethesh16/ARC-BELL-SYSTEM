import 'package:college_bell/main.dart';
import 'package:college_bell/screens/admin_dashboard.dart';
import 'package:college_bell/screens/department_control_screen.dart';
import 'package:college_bell/screens/login_screen.dart';
import 'package:college_bell/screens/manage_departments_screen.dart';
import 'package:college_bell/screens/secretary_dashboard.dart';
import 'package:college_bell/services/department_service.dart';
import 'package:college_bell/services/firebase_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDepartmentService extends DepartmentService {
  final departments = [const Department('icbs', 'Mathematics', managed: false)];
  final logins = <(String, String)>[];
  int ringRequests = 0;
  int deletionRequests = 0;

  @override
  Future<void> deleteDepartment(String id, String password) async {
    deletionRequests++;
    if (password != 'test-password') {
      throw const FirebaseApiException('Password verification failed.');
    }
    departments.removeWhere((department) => department.id == id);
  }

  @override
  Future<String> getMode(String dept, {bool managed = false}) async =>
      'college';

  @override
  Future<List<int>> getSchedule(String dept, String mode,
          {bool managed = false}) async =>
      [540, 630];

  @override
  Future<void> triggerManualRing(String dept, {bool managed = false}) async {
    ringRequests++;
  }

  @override
  Future<List<Department>> getDepartments() async => List.of(departments);

  @override
  Future<Department> getAssignedDepartment(String id) async =>
      departments.singleWhere((department) => department.id == id);

  @override
  Future<Department> createDepartment(String name) async {
    final department = Department('dept1', name, managed: true);
    departments.add(department);
    return department;
  }

  @override
  Future<void> createSecretary(String id, String email, String password) async {
    logins.add((id, email));
  }
}

void main() {
  testWidgets('department deletion requires a password and keeps Mathematics',
      (tester) async {
    final service = FakeDepartmentService()
      ..departments.add(const Department('dept1', 'Physics', managed: true));
    await tester.pumpWidget(CollegeBellApp(
      home: ManageDepartmentsScreen(service: service),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    await tester.ensureVisible(find.text('Delete'));
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Physics?'), findsOneWidget);
    await tester.tap(find.text('Delete Department'));
    await tester.pumpAndSettle();
    expect(service.deletionRequests, 0);
    final field = find.widgetWithText(TextFormField, 'Your account password');
    await tester.enterText(field, 'wrong-password');
    await tester.tap(find.text('Delete Department'));
    await tester.pumpAndSettle();
    expect(find.text('Password verification failed.'), findsOneWidget);
    expect(service.departments.length, 2);
    await tester.enterText(field, 'test-password');
    await tester.tap(find.text('Delete Department'));
    await tester.pumpAndSettle();
    expect(service.departments.single.id, 'icbs');
    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });
  testWidgets(
      'sign-in fits a narrow window with large text and validates input',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(CollegeBellApp(
        home: MediaQuery(
      data: const MediaQueryData(
          size: Size(500, 700), textScaler: TextScaler.linear(1.4)),
      child: LoginScreen(onAuthenticated: (_) {}),
    )));
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
  });

  testWidgets('admin can find a department by name or ID', (tester) async {
    final service = FakeDepartmentService()
      ..departments.add(const Department('dept1', 'Physics', managed: true));
    await tester.pumpWidget(CollegeBellApp(
        home: AdminDashboard(service: service, onSignOut: () async {})));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'dept1');
    await tester.pumpAndSettle();
    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('Mathematics'), findsNothing);
  });

  testWidgets(
      'manual ring names the department and cancellation sends no command',
      (tester) async {
    final service = FakeDepartmentService();
    await tester.pumpWidget(CollegeBellApp(
        home: DepartmentControlScreen(
      dept: 'dept1',
      departmentName: 'Physics',
      managed: true,
      service: service,
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Ring Now'));
    await tester.tap(find.text('Ring Now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ring the bell in Physics?'), findsOneWidget);
    expect(service.ringRequests, 0);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.ringRequests, 0);
  });
  testWidgets(
      'legacy department has no edits; optional setup creates one department and login',
      (tester) async {
    final service = FakeDepartmentService();
    await tester.pumpWidget(
        MaterialApp(home: ManageDepartmentsScreen(service: service)));
    await tester.pumpAndSettle();

    expect(find.text('Mathematics'), findsOneWidget);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Create Secretary Login'), findsNothing);
    await tester.tap(find.text('Add Department'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Physics');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('Save Department'));
    await tester.pumpAndSettle();

    expect(find.text('Create Secretary Login'), findsOneWidget);
    expect(
        find.widgetWithText(TextFormField, 'Initial password'), findsOneWidget);
    await tester.enterText(
        find.byType(TextFormField).at(0), 'physics@example.test');
    await tester.enterText(
        find.byType(TextFormField).at(1), 'TestPasswordOnly!');
    await tester.tap(find.text('Create Login'));
    await tester.pumpAndSettle();

    expect(service.logins, [('dept1', 'physics@example.test')]);
    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('Rename'), findsOneWidget);
  });

  testWidgets('secretary dashboard has no management controls', (tester) async {
    final service = FakeDepartmentService()
      ..departments.add(const Department('dept1', 'Physics', managed: true));
    await tester.pumpWidget(CollegeBellApp(
        home: SecretaryDashboard(
      service: service,
      onSignOut: () async {},
      userData: {
        'role': 'secretary',
        'departments': {'dept1': true, 'icbs': false}
      },
    )));
    await tester.pumpAndSettle();

    expect(find.text('Physics'), findsOneWidget);
    expect(find.text('Mathematics'), findsNothing);
    expect(find.text('Manage Departments'), findsNothing);
    expect(find.text('Add Department'), findsNothing);
    expect(find.text('Create Secretary Login'), findsNothing);
  });
}
