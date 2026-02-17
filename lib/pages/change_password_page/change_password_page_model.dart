import '/flutter_flow/flutter_flow_util.dart';
import 'change_password_page_widget.dart' show ChangePasswordPageWidget;
import 'package:flutter/material.dart';

class ChangePasswordPageModel
    extends FlutterFlowModel<ChangePasswordPageWidget> {
  ///  State fields for stateful widgets in this page.

  final unfocusNode = FocusNode();
  // State field for CurrentPassword.
  FocusNode? currentPasswordFocusNode;
  TextEditingController? currentPasswordController;
  late bool currentPasswordVisibility;
  String? Function(BuildContext, String?)? currentPasswordControllerValidator;
  // State field for NewPassword.
  FocusNode? newPasswordFocusNode;
  TextEditingController? newPasswordController;
  late bool newPasswordVisibility;
  String? Function(BuildContext, String?)? newPasswordControllerValidator;
  // State field for ConfirmPassword.
  FocusNode? confirmPasswordFocusNode;
  TextEditingController? confirmPasswordController;
  late bool confirmPasswordVisibility;
  String? Function(BuildContext, String?)? confirmPasswordControllerValidator;

  @override
  void initState(BuildContext context) {
    currentPasswordVisibility = false;
    newPasswordVisibility = false;
    confirmPasswordVisibility = false;
  }

  @override
  void dispose() {
    unfocusNode.dispose();
    currentPasswordFocusNode?.dispose();
    currentPasswordController?.dispose();

    newPasswordFocusNode?.dispose();
    newPasswordController?.dispose();

    confirmPasswordFocusNode?.dispose();
    confirmPasswordController?.dispose();
  }
}
