import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_widgets.dart';

class EditProfileScreen extends StatefulWidget {
	const EditProfileScreen({super.key});

	@override
	State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
	final _photoUrlController = TextEditingController();
	final _nameController = TextEditingController();
	final _phoneController = TextEditingController();
	final _nationalityController = TextEditingController();
	final _countryController = TextEditingController();
	final _universityController = TextEditingController();
	final _departmentController = TextEditingController();
	final _degreeController = TextEditingController();

	bool _isLoading = true;
	bool _isSaving = false;
	bool _canEditDepartment = true;
	bool _canEditDegree = true;

	final List<String> _countries = [
		'Australia',
		'Austria',
		'Bangladesh',
		'Belgium',
		'Canada',
		'China',
		'Denmark',
		'Finland',
		'France',
		'Germany',
		'India',
		'Ireland',
		'Italy',
		'Japan',
		'Netherlands',
		'New Zealand',
		'Norway',
		'Singapore',
		'South Korea',
		'Spain',
		'Sweden',
		'Switzerland',
		'UK',
		'USA',
	];

	final List<String> _universities = [
		'PSTU',
		'BUET',
		'DU',
		'RUET',
		'KUET',
		'CUET',
		'SUST',
		'NSU',
		'BRAC University',
		'AIUB',
		'EWU',
		'MIT',
		'Harvard University',
		'Stanford University',
		'University of Oxford',
		'University of Cambridge',
		'ETH Zurich',
		'National University of Singapore',
		'Tsinghua University',
		'Technion',
		'Tokyo Institute of Technology',
		'University of Melbourne',
		'University of Toronto',
		'University of British Columbia',
		'University of Sydney',
		'University of Waterloo',
		'Imperial College London',
		'EPFL',
		'TU Munich',
		'TU Delft',
		'RWTH Aachen',
	];

	final List<String> _departments = [
		'CSE',
		'EEE',
		'BBA',
		'Meachanical',
		'Civil',
    'Textile',
		'Biomedical',
		'Architecture',
    
	];

	final List<String> _degrees = [
		'Undergraduate',
		'Masters',
		'PhD',
	];

	@override
	void initState() {
		super.initState();
		_photoUrlController.addListener(_handlePhotoUrlChanged);
		_loadProfile();
	}

	void _handlePhotoUrlChanged() {
		if (mounted) {
			setState(() {});
		}
	}

	@override
	void dispose() {
		_photoUrlController.removeListener(_handlePhotoUrlChanged);
		_photoUrlController.dispose();
		_nameController.dispose();
		_phoneController.dispose();
		_nationalityController.dispose();
		_countryController.dispose();
		_universityController.dispose();
		_departmentController.dispose();
		_degreeController.dispose();
		super.dispose();
	}

	Future<void> _loadProfile() async {
		final currentUser = FirebaseAuth.instance.currentUser;
		if (currentUser == null) {
			setState(() => _isLoading = false);
			return;
		}

		try {
			final snapshot = await FirebaseFirestore.instance
					.collection('users')
					.doc(currentUser.uid)
					.get();

			final data = snapshot.data();
			if (data != null) {
				_photoUrlController.text =
						(data['photoUrl'] ?? currentUser.photoURL ?? '').toString();
				_nameController.text = (data['name'] ?? currentUser.displayName ?? '').toString();
				_phoneController.text = (data['phone'] ?? '').toString();
				_nationalityController.text = (data['nationality'] ?? '').toString();
				_countryController.text = (data['country'] ?? '').toString();
				_universityController.text = (data['university'] ?? '').toString();
				_departmentController.text = (data['department'] ?? '').toString();
				_degreeController.text = (data['degree'] ?? '').toString();
			} else {
				_photoUrlController.text = currentUser.photoURL ?? '';
				_nameController.text = currentUser.displayName ?? '';
			}
		} catch (e) {
			if (mounted) {
				_showMessage('Unable to load profile data. Please try again.');
			}
		} finally {
			if (mounted) {
				setState(() => _isLoading = false);
			}
		}
	}

	Future<void> _saveProfile() async {
		final currentUser = FirebaseAuth.instance.currentUser;
		if (currentUser == null) {
			_showMessage('Please log in to update your profile.');
			return;
		}

		final name = _nameController.text.trim();
		if (name.isEmpty) {
			_showMessage('Full name is required.');
			return;
		}

		setState(() => _isSaving = true);
		try {
			await FirebaseFirestore.instance
					.collection('users')
					.doc(currentUser.uid)
					.set({
				'photoUrl': _photoUrlController.text.trim(),
				'name': name,
				'phone': _phoneController.text.trim(),
				'nationality': _nationalityController.text.trim(),
				'country': _countryController.text.trim(),
				'university': _universityController.text.trim(),
				'department': _departmentController.text.trim(),
				'degree': _degreeController.text.trim(),
				'profileCompleted': true,
				'updatedAt': Timestamp.now(),
			}, SetOptions(merge: true));

			await currentUser.updateDisplayName(name);
			await currentUser.updatePhotoURL(_photoUrlController.text.trim());

			if (mounted) {
				_showMessage('Profile updated successfully.');
			}
		} catch (e) {
			if (mounted) {
				_showMessage('Failed to update profile. Please try again.');
			}
		} finally {
			if (mounted) {
				setState(() => _isSaving = false);
			}
		}
	}

	void _showMessage(String message) {
		ScaffoldMessenger.of(context).showSnackBar(
			SnackBar(content: Text(message)),
		);
	}

	Future<void> _openSingleSelectSheet({
		required String title,
		required List<String> options,
		required TextEditingController controller,
	}) async {
		final searchController = TextEditingController();
		await showModalBottomSheet<void>(
			context: context,
			isScrollControlled: true,
			backgroundColor: Colors.white,
			shape: const RoundedRectangleBorder(
				borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
			),
			builder: (context) => StatefulBuilder(
				builder: (context, setSheetState) {
					final rawQuery = searchController.text.trim();
					final query = rawQuery.toLowerCase();
					final filtered = options
							.where((item) => item.toLowerCase().contains(query))
							.toList();
					final hasExactMatch =
						rawQuery.isNotEmpty && options.any((item) => item.toLowerCase() == query);

					return SafeArea(
						child: Padding(
							padding: EdgeInsets.only(
								left: 20,
								right: 20,
								top: 16,
								bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
							),
							child: Column(
								mainAxisSize: MainAxisSize.min,
								children: [
									Row(
										children: [
											Expanded(
												child: Text(
													title,
													style: const TextStyle(
														fontSize: 18,
														fontWeight: FontWeight.w600,
														color: sbText,
													),
												),
											),
											TextButton(
												onPressed: () => Navigator.of(context).pop(),
												child: const Text(
													'Close',
													style: TextStyle(
														fontSize: 14,
														fontWeight: FontWeight.w600,
														color: sbPrimary,
													),
												),
											),
										],
									),
									const SizedBox(height: 12),
									TextField(
										controller: searchController,
										onChanged: (_) => setSheetState(() {}),
										decoration: InputDecoration(
											hintText: 'Search',
											hintStyle: const TextStyle(
												fontSize: 14,
												fontWeight: FontWeight.w400,
												color: sbHintText,
											),
											prefixIcon: const Icon(Icons.search, color: sbPrimary),
											filled: true,
											fillColor: sbBackground,
											contentPadding:
												const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
											border: OutlineInputBorder(
												borderRadius: BorderRadius.circular(12),
												borderSide: BorderSide.none,
											),
										),
									),
									const SizedBox(height: 12),
									Flexible(
										child: ListView.separated(
											shrinkWrap: true,
											itemCount: filtered.length +
													(hasExactMatch || rawQuery.isEmpty ? 0 : 1),
											separatorBuilder: (_, __) =>
													const Divider(height: 1, color: sbBorder),
											itemBuilder: (context, index) {
												final showAddRow =
													!hasExactMatch && rawQuery.isNotEmpty && index == 0;
												if (showAddRow) {
													return ListTile(
														onTap: () {
															setState(() {
																controller.text = rawQuery;
															});
															Navigator.of(context).pop();
														},
														contentPadding: EdgeInsets.zero,
														leading: const Icon(Icons.add_circle_outline, color: sbPrimary),
														title: Text(
															'Add "$rawQuery"',
															style: const TextStyle(
																fontSize: 14,
																fontWeight: FontWeight.w600,
																color: sbPrimary,
															),
														),
													);
												}

												final adjustedIndex =
													!hasExactMatch && rawQuery.isNotEmpty ? index - 1 : index;
												final item = filtered[adjustedIndex];
												final isSelected =
														controller.text.trim() == item;

												return ListTile(
													onTap: () {
														setState(() {
															controller.text = item;
														});
														Navigator.of(context).pop();
													},
													contentPadding: EdgeInsets.zero,
													leading: Icon(
														isSelected
															? Icons.check_circle
															: Icons.circle_outlined,
														color: isSelected ? sbPrimary : sbMutedText,
													),
													title: Text(
														item,
														style: const TextStyle(
															fontSize: 14,
															fontWeight: FontWeight.w500,
															color: sbText,
														),
													),
												);
											},
										),
									),
								],
							),
						),
					);
				},
			),
		);
	}

	@override
	Widget build(BuildContext context) => Scaffold(
				backgroundColor: sbBackground,
				appBar: AppBar(
					backgroundColor: Colors.white,
					elevation: 0,
					title: const Text(
						'Edit Profile',
						style: TextStyle(
							fontSize: 20,
							fontWeight: FontWeight.w600,
							color: sbText,
						),
					),
					centerTitle: true,
					leading: IconButton(
						icon: const Icon(Icons.arrow_back_rounded, color: sbText),
						onPressed: () => Navigator.of(context).pop(),
					),
				),
				body: _isLoading
						? const Center(child: CircularProgressIndicator(color: sbPrimary))
						: SafeArea(
								child: SingleChildScrollView(
									padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
									child: Column(
										crossAxisAlignment: CrossAxisAlignment.stretch,
										children: [
											const Text(
												'Tell us more about you',
												style: TextStyle(
													fontSize: 18,
													fontWeight: FontWeight.w600,
													color: sbText,
												),
											),
											const SizedBox(height: 8),
											const Text(
												'Keep your profile updated to improve scholarship matches.',
												style: TextStyle(
													fontSize: 13,
													fontWeight: FontWeight.w400,
													color: sbSecondaryText,
												),
											),
											const SizedBox(height: 24),
											CircleAvatar(
												radius: 50,
												backgroundColor: Colors.white,
												backgroundImage: _photoUrlController.text.trim().startsWith('http')
														? NetworkImage(_photoUrlController.text.trim())
														: null,
												child: _photoUrlController.text.trim().isEmpty
														? const Icon(Icons.person, size: 50, color: sbMutedText)
														: null,
											),
											const SizedBox(height: 16),
											ProfileTextField(
												controller: _photoUrlController,
												hintText: 'Profile Picture URL',
												prefixIcon: Icons.image_outlined,
												keyboardType: TextInputType.url,
											),
											const SizedBox(height: 16),
											ProfileTextField(
												controller: _nameController,
												hintText: 'Full Name',
												prefixIcon: Icons.person_outline,
											),
											const SizedBox(height: 16),
											ProfileTextField(
												controller: _phoneController,
												hintText: 'Phone Number',
												prefixIcon: Icons.phone_outlined,
												keyboardType: TextInputType.phone,
											),
											const SizedBox(height: 16),
											ProfileTextField(
												controller: _nationalityController,
												hintText: 'Nationality',
												prefixIcon: Icons.flag_outlined,
											),
											const SizedBox(height: 16),
											_buildSelectField(
												label: 'Country',
												controller: _countryController,
												prefixIcon: Icons.public_outlined,
												onTap: () => _openSingleSelectSheet(
													title: 'Select Country',
													options: _countries,
													controller: _countryController,
												),
											),
											const SizedBox(height: 16),
											_buildSelectField(
												label: 'University',
												controller: _universityController,
												prefixIcon: Icons.school_outlined,
												onTap: () => _openSingleSelectSheet(
													title: 'Select University',
													options: _universities,
													controller: _universityController,
												),
											),
											const SizedBox(height: 16),
											_buildLockedSelectField(
												label: 'Department',
												controller: _departmentController,
												prefixIcon: Icons.account_balance_outlined,
												canEdit: _canEditDepartment,
												onEdit: () {
													setState(() => _canEditDepartment = true);
													_openSingleSelectSheet(
														title: 'Select Department',
														options: _departments,
														controller: _departmentController,
													).whenComplete(() {
														setState(() => _canEditDepartment = false);
													});
												},
											),
											const SizedBox(height: 16),
											_buildLockedSelectField(
												label: 'Degree',
												controller: _degreeController,
												prefixIcon: Icons.book_outlined,
												canEdit: _canEditDegree,
												onEdit: () {
													setState(() => _canEditDegree = true);
													_openSingleSelectSheet(
														title: 'Select Degree',
														options: _degrees,
														controller: _degreeController,
													).whenComplete(() {
														setState(() => _canEditDegree = false);
													});
												},
											),
											const SizedBox(height: 28),
											ProfilePrimaryButton(
												title: 'Save',
												onPressed: _saveProfile,
												isLoading: _isSaving,
											),
											const SizedBox(height: 12),
										],
									),
								),
							),
			);

			Widget _buildSelectField({
				required String label,
				required TextEditingController controller,
				required IconData prefixIcon,
				required VoidCallback onTap,
			}) {
				final value = controller.text.trim();
				return GestureDetector(
					onTap: onTap,
					child: Container(
						padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
						decoration: BoxDecoration(
							color: Colors.white,
							borderRadius: BorderRadius.circular(12),
							border: Border.all(color: sbBorder, width: 1.5),
						),
						child: Row(
							children: [
								Icon(prefixIcon, color: sbPrimary, size: 22),
								const SizedBox(width: 12),
								Expanded(
									child: Text(
										value.isEmpty ? label : value,
										style: TextStyle(
											fontSize: 14,
											fontWeight: FontWeight.w500,
											color: value.isEmpty ? sbHintText : sbText,
										),
									),
								),
								const Icon(Icons.expand_more, color: sbPrimary, size: 24),
							],
						),
					),
				);
			}

			Widget _buildLockedSelectField({
				required String label,
				required TextEditingController controller,
				required IconData prefixIcon,
				required bool canEdit,
				required VoidCallback onEdit,
			}) {
				final value = controller.text.trim();
				return Container(
					padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
					decoration: BoxDecoration(
						color: Colors.white,
						borderRadius: BorderRadius.circular(12),
						border: Border.all(color: sbBorder, width: 1.5),
					),
					child: Row(
						children: [
							Icon(prefixIcon, color: sbPrimary, size: 22),
							const SizedBox(width: 12),
							Expanded(
								child: Text(
									value.isEmpty ? label : value,
									style: TextStyle(
										fontSize: 14,
										fontWeight: FontWeight.w500,
										color: value.isEmpty ? sbHintText : sbText,
									),
								),
							),
							IconButton(
								onPressed: onEdit,
								icon: Icon(
									Icons.edit_outlined,
									color: canEdit ? sbPrimary : sbMutedText,
								),
							),
						],
					),
				);
			}
}
