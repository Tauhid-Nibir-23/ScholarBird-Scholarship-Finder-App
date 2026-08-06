import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/banner_image_service.dart';
import 'admin_ui.dart';
import 'widgets/admin_dialogs.dart';
import 'widgets/admin_image_picker.dart';

class AddScholarshipPage extends StatefulWidget {
  const AddScholarshipPage({super.key, this.scholarship});

  final DocumentSnapshot<Map<String, dynamic>>? scholarship;

  @override
  State<AddScholarshipPage> createState() => _AddScholarshipPageState();
}

class _AddScholarshipPageState extends State<AddScholarshipPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _countryController = TextEditingController();
  final _degreeController = TextEditingController();
  final _fieldController = TextEditingController();
  final _deadlineController = TextEditingController();
  final _fundingController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _officialLinkController = TextEditingController();
  final _minimumCgpaController = TextEditingController();
  bool _ieltsRequired = false;
  bool _researchRequired = false;
  bool _isSaving = false;

  bool get _isEditing => widget.scholarship != null;

  @override
  void initState() {
    super.initState();
    final data = widget.scholarship?.data();
    if (data == null) return;
    _titleController.text = data['title']?.toString() ?? '';
    _countryController.text = data['country']?.toString() ?? '';
    _degreeController.text = data['degree']?.toString() ?? '';
    _fieldController.text = data['field']?.toString() ?? '';
    _deadlineController.text = _dateText(data['deadline']);
    _fundingController.text =
        data['funding']?.toString() ?? data['fundingType']?.toString() ?? data['amount']?.toString() ?? '';
    _imageUrlController.text = data['image']?.toString() ?? '';
    _descriptionController.text = data['description']?.toString() ?? '';
    _officialLinkController.text = data['sourceUrl']?.toString() ?? data['link']?.toString() ?? '';
    _minimumCgpaController.text = data['minCgpa']?.toString() ?? '';
    _ieltsRequired = data['ieltsRequired'] == true;
    _researchRequired = data['researchRequired'] == true;
  }

  @override
  void dispose() {
    for (final controller in [
      _titleController,
      _countryController,
      _degreeController,
      _fieldController,
      _deadlineController,
      _fundingController,
      _imageUrlController,
      _descriptionController,
      _officialLinkController,
      _minimumCgpaController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _selectDeadline() async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (selected != null) {
      setState(() => _deadlineController.text =
          '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}');
    }
  }

  String? get _scholarshipId => widget.scholarship?.id;

  Future<String?> _uploadBanner(ImageSource source) async {
    final id = _scholarshipId;
    if (id == null) {
      // New scholarship: save first so the file has a stable id to
      // namespace under in Supabase Storage.
      if (!(_formKey.currentState?.validate() ?? false)) return null;
      final docRef = await FirebaseFirestore.instance
          .collection('scholarships')
          .add({
        'title': _titleController.text.trim(),
        'country': _countryController.text.trim(),
        'degree': _degreeController.text.trim(),
        'field': _fieldController.text.trim(),
        'deadline': _deadlineController.text.trim(),
        'funding': _fundingController.text.trim(),
        'fundingType': _fundingController.text.trim(),
        'amount': _fundingController.text.trim(),
        'image': _imageUrlController.text.trim(),
        'description': _descriptionController.text.trim(),
        'link': _officialLinkController.text.trim(),
        'sourceUrl': _officialLinkController.text.trim(),
        'minCgpa': _minimumCgpaController.text.trim(),
        'ieltsRequired': _ieltsRequired,
        'researchRequired': _researchRequired,
        'isFeatured': false,
        'isHidden': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final url = source == ImageSource.gallery
          ? await BannerImageService.instance
              .pickAndUploadFromGallery(docRef.id)
          : await BannerImageService.instance
              .pickAndUploadFromCamera(docRef.id);
      if (url != null) {
        setState(() => _imageUrlController.text = url);
      }
      return url;
    }

    final url = source == ImageSource.gallery
        ? await BannerImageService.instance
            .pickAndUploadFromGallery(id)
        : await BannerImageService.instance
            .pickAndUploadFromCamera(id);
    if (url != null) {
      setState(() => _imageUrlController.text = url);
    }
    return url;
  }

  Future<void> _removeBanner() async {
    final id = _scholarshipId;
    if (id == null) {
      setState(() => _imageUrlController.text = '');
      return;
    }
    await BannerImageService.instance.removeBannerImage(id);
    setState(() => _imageUrlController.text = '');
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    final data = <String, dynamic>{
      'title': _titleController.text.trim(),
      'country': _countryController.text.trim(),
      'degree': _degreeController.text.trim(),
      'field': _fieldController.text.trim(),
      'deadline': _deadlineController.text.trim(),
      'funding': _fundingController.text.trim(),
      'fundingType': _fundingController.text.trim(),
      'amount': _fundingController.text.trim(),
      'image': _imageUrlController.text.trim(),
      'description': _descriptionController.text.trim(),
      'link': _officialLinkController.text.trim(),
      'sourceUrl': _officialLinkController.text.trim(),
      'minCgpa': _minimumCgpaController.text.trim(),
      'ieltsRequired': _ieltsRequired,
      'researchRequired': _researchRequired,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (_isEditing) {
        await widget.scholarship!.reference.update(data);
      } else {
        await FirebaseFirestore.instance.collection('scholarships').add({
          ...data,
          'isFeatured': false,
          'isHidden': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        AdminDialogs.error(context, 'Could not save scholarship: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: AdminTheme.data(context),
        child: Scaffold(
          appBar: AppBar(
              title: Text(_isEditing ? 'Edit Scholarship' : 'Add Scholarship')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              _isEditing
                                  ? 'Update scholarship details'
                                  : 'Create a new opportunity',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text(
                              'Fields marked with an asterisk are required.'),
                          const SizedBox(height: 28),
                          _FormSection(title: 'Core details', children: [
                            _field(_titleController, 'Title', required: true),
                            _field(_countryController, 'Country',
                                required: true),
                            _field(_degreeController, 'Degree', required: true),
                            _field(_fieldController, 'Field of study',
                                required: true),
                            TextFormField(
                                controller: _deadlineController,
                                readOnly: true,
                                onTap: _selectDeadline,
                                decoration: const InputDecoration(
                                    labelText: 'Deadline *',
                                    suffixIcon: Icon(Icons.calendar_today),
                                    border: OutlineInputBorder()),
                                validator: _required),
                            _field(_fundingController, 'Funding',
                                required: true),
                            const SizedBox(height: 8),
                            Text('Banner image',
                                style: Theme.of(context).textTheme.titleSmall),
                            const SizedBox(height: 6),
                            const Text(
                              'Upload a 16:9 hero image. Stored in Supabase; '
                              'URL is mirrored to Firestore on save.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AdminPalette.body,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: AdminImagePicker(
                                photoUrl:
                                    _imageUrlController.text.trim().isEmpty
                                        ? null
                                        : _imageUrlController.text.trim(),
                                title: 'Scholarship banner',
                                subtitle:
                                    'Recommended: 1600x900 (16:9).',
                                fallbackLabel: 'Banner',
                                shape: AdminImagePickerShape.rounded,
                                aspectRatio: 16 / 9,
                                onUploadFromGallery: () =>
                                    _uploadBanner(ImageSource.gallery),
                                onUploadFromCamera: () =>
                                    _uploadBanner(ImageSource.camera),
                                onRemove: _removeBanner,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 20),
                          _FormSection(title: 'Eligibility & links', children: [
                            _field(_minimumCgpaController, 'Minimum CGPA',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true)),
                            _field(_imageUrlController, 'Image URL',
                                keyboardType: TextInputType.url),
                            _field(_officialLinkController, 'Official Link',
                                keyboardType: TextInputType.url),
                            SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _ieltsRequired,
                                onChanged: (value) =>
                                    setState(() => _ieltsRequired = value),
                                title: const Text('IELTS Required')),
                            SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _researchRequired,
                                onChanged: (value) =>
                                    setState(() => _researchRequired = value),
                                title: const Text('Research Required')),
                          ]),
                          const SizedBox(height: 20),
                          _FormSection(title: 'Description', children: [
                            TextFormField(
                                controller: _descriptionController,
                                minLines: 6,
                                maxLines: 10,
                                decoration: const InputDecoration(
                                    labelText: 'Description *',
                                    alignLabelWithHint: true,
                                    border: OutlineInputBorder()),
                                validator: _required),
                          ]),
                          const SizedBox(height: 28),
                          Align(
                              alignment: Alignment.centerRight,
                              child: FilledButton.icon(
                                  onPressed: _isSaving ? null : _save,
                                  icon: _isSaving
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.save),
                                  label: Text(_isSaving
                                      ? 'Saving...'
                                      : 'Save scholarship'))),
                        ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String _dateText(dynamic value) {
    final date = value is Timestamp
        ? value.toDate()
        : value is DateTime
            ? value
            : null;
    if (date == null) return value?.toString() ?? '';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _field(TextEditingController controller, String label,
          {bool required = false, TextInputType? keyboardType}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
                labelText: required ? '$label *' : label,
                border: const OutlineInputBorder()),
            validator: required ? _required : null),
      );
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => AdminSurface(
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            ...children
          ]),
        ),
      );
}
