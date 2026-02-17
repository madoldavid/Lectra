import '/flutter_flow/flutter_flow_util.dart';
import 'update_email_page_widget.dart' show UpdateEmailPageWidget;
import 'package:flutter/material.dart';

class UpdateEmailPageModel extends FlutterFlowModel<UpdateEmailPageWidget> {
  ///  State fields for stateful widgets in this page.

  final unfocusNode = FocusNode();
  // State field for NewEmail.
  FocusNode? newEmailFocusNode;
  TextEditingController? newEmailController;
  String? Function(BuildContext, String?)? newEmailControllerValidator;

  @override
  void initState(BuildContext context) {}

  @override
  void dispose() {
    unfocusNode.dispose();
    newEmailFocusNode?.dispose();
    newEmailController?.dispose();
  }
}
