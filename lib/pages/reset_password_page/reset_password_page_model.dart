import '/flutter_flow/flutter_flow_util.dart';
import 'reset_password_page_widget.dart' show ResetPasswordPageWidget;
import 'package:flutter/material.dart';

class ResetPasswordPageModel extends FlutterFlowModel<ResetPasswordPageWidget> {
  final unfocusNode = FocusNode();
  FocusNode? newPasswordFocusNode;
  TextEditingController? newPasswordController;
  FocusNode? confirmPasswordFocusNode;
  TextEditingController? confirmPasswordController;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    unfocusNode.dispose();
    newPasswordFocusNode?.dispose();
    newPasswordController?.dispose();
    confirmPasswordFocusNode?.dispose();
    confirmPasswordController?.dispose();
  }
}
