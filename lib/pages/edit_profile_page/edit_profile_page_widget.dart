import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '/auth/supabase_auth/auth_util.dart';
import '/backend/supabase/supabase.dart';
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_widgets.dart';
import 'package:go_router/go_router.dart';

class EditProfilePageWidget extends StatefulWidget {
  const EditProfilePageWidget({super.key});

  static String routeName = 'EditProfilePage';
  static String routePath = '/editProfilePage';

  @override
  State<EditProfilePageWidget> createState() => _EditProfilePageWidgetState();
}

class _EditProfilePageWidgetState extends State<EditProfilePageWidget> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _displayNameController;
  XFile? _imageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    authManager.refreshUser();
    _displayNameController =
        TextEditingController(text: currentUserDisplayName);
  }

  Future<String?> _uploadProfilePicture() async {
    if (_imageFile == null) return null;

    final file = File(_imageFile!.path);
    final fileExtension = _imageFile!.path.split('.').last;
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
    final userId = currentUserUid.isNotEmpty
        ? currentUserUid
        : DateTime.now().millisecondsSinceEpoch.toString();
    final filePath = 'public/profile_pictures/$userId/$fileName';

    try {
      await SupaFlow.client.storage.from('user_files').upload(
            filePath,
            file,
            fileOptions: const FileOptions(upsert: true),
          );
      return SupaFlow.client.storage.from('user_files').getPublicUrl(filePath);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload image: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _updateProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final photoUrl = await _uploadProfilePicture();
      final newDisplayName = _displayNameController.text;

      final updateData = <String, dynamic>{};
      if (photoUrl != null) {
        updateData['photo_url'] = photoUrl;
      }
      if (newDisplayName != currentUserDisplayName) {
        updateData['full_name'] = newDisplayName;
      }

      try {
        if (updateData.isNotEmpty) {
          await authManager.updateCurrentUser(updateData);
        }
      } on AuthException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unable to update profile: ${e.message}')),
          );
        }
        setState(() {
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isLoading = false;
      });

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
      context.pop();
    }
  }

  Future<void> _pickImage() async {
    final pickedFile =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _imageFile = pickedFile;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: CircleAvatar(
                        radius: 50,
                        backgroundImage: _imageFile != null
                            ? FileImage(File(_imageFile!.path))
                            : (currentUserPhoto.isNotEmpty
                                ? NetworkImage(currentUserPhoto)
                                : null) as ImageProvider?,
                        child: _imageFile == null && currentUserPhoto.isEmpty
                            ? const Icon(Icons.camera_alt, size: 50)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a display name';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    FFButtonWidget(
                      onPressed: _updateProfile,
                      text: 'Save Changes',
                      options: FFButtonOptions(
                        width: double.infinity,
                        height: 50,
                        color: FlutterFlowTheme.of(context).primary,
                        textStyle:
                            FlutterFlowTheme.of(context).titleSmall.override(
                                  fontFamily: 'Readex Pro',
                                  color: Colors.white,
                                ),
                        elevation: 3,
                        borderSide: const BorderSide(
                          color: Colors.transparent,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
