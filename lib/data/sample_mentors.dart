/// Sample reference fixtures used by the Reference Point UI.
///
/// This file is intentionally pure-data: it exposes a [sampleMentors] list
/// that the screen consumes directly. Replacing it with a Firestore-backed
/// repository later is a one-line swap in the screen — the UI is wired
/// against the [Mentor] model, not against this constant.
///
/// Note: branded as "Reference Point" in the UI (formerly "Mentor Hub").
import '../models/mentor.dart';

/// Mock data spanning every department in the filter chip row.
const List<Mentor> sampleMentors = <Mentor>[
  // ── Computer Science ────────────────────────────────────────────────────
  Mentor(
    id: 'cs-001',
    name: 'Dr. Ayesha Rahman',
    designation: 'Professor',
    department: MentorDepartment.computerScience,
    university: 'North South University',
    researchInterests: ['Machine Learning', 'Natural Language Processing', 'Computer Vision'],
    bio:
        'Leads the Language Intelligence Lab, focused on low-resource NLP '
        'and multilingual question answering. Open to undergraduate research '
        'collaborations on capstone projects.',
    email: 'ayesha.rahman@northsouth.edu',
    phone: '+880-2-55668200 Ext. 2145',
    officeRoom: 'NAC 512',
    availableDays: ['Sun', 'Tue', 'Thu'],
    availableTime: '11:00 AM – 1:00 PM',
  ),
  Mentor(
    id: 'cs-002',
    name: 'Dr. Imran Hossain',
    designation: 'Associate Professor',
    department: MentorDepartment.computerScience,
    university: 'BRAC University',
    researchInterests: ['Cybersecurity', 'Cryptography', 'Network Forensics'],
    bio:
        'Consultant for national CERT teams and mentor for Capture-the-Flag '
        'competitions. Happy to host students interested in security research.',
    email: 'imran.hossain@bracu.ac.bd',
    phone: '+880-2-9844051 Ext. 4012',
    officeRoom: 'UB 304',
    availableDays: ['Mon', 'Wed'],
    availableTime: '2:00 PM – 4:00 PM',
  ),
  Mentor(
    id: 'cs-003',
    name: 'Dr. Sara Khan',
    designation: 'Assistant Professor',
    department: MentorDepartment.computerScience,
    university: 'University of Dhaka',
    researchInterests: ['HCI', 'Accessibility', 'Educational Technology'],
    bio:
        'Researches accessible computing for learners with disabilities. '
        'Runs a weekly reading group open to undergraduate visitors.',
    email: 'sara.khan@du.ac.bd',
    phone: '+880-2-9661900 Ext. 4280',
    officeRoom: 'CSE 218',
    availableDays: ['Tue', 'Thu', 'Sat'],
    availableTime: '10:00 AM – 12:00 PM',
  ),

  // ── Electrical Engineering ──────────────────────────────────────────────
  Mentor(
    id: 'ee-001',
    name: 'Dr. Mohammad Tariq',
    designation: 'Professor',
    department: MentorDepartment.electricalEngineering,
    university: 'BUET',
    researchInterests: ['Renewable Energy', 'Power Systems', 'Smart Grid'],
    bio:
        'Twenty years in high-voltage research with a focus on grid '
        'integration of renewables. Accepts a limited number of senior '
        'capstone mentees each semester.',
    email: 'm.tariq@eee.buet.ac.bd',
    phone: '+880-2-9665650 Ext. 7321',
    officeRoom: 'EEE 410',
    availableDays: ['Sun', 'Wed'],
    availableTime: '3:00 PM – 5:00 PM',
  ),
  Mentor(
    id: 'ee-002',
    name: 'Dr. Nadia Akter',
    designation: 'Associate Professor',
    department: MentorDepartment.electricalEngineering,
    university: 'Ahsanullah University of Science & Technology',
    researchInterests: ['VLSI Design', 'Embedded Systems', 'IoT'],
    bio:
        'Designs low-power SoCs for edge devices. Maintains a small lab of '
        'student engineers building IoT prototypes for agriculture.',
    email: 'nadia.akter@aust.edu',
    phone: '+880-2-8870422 Ext. 605',
    officeRoom: 'TE 207',
    availableDays: ['Mon', 'Thu'],
    availableTime: '1:00 PM – 3:00 PM',
  ),

  // ── Business ────────────────────────────────────────────────────────────
  Mentor(
    id: 'bus-001',
    name: 'Dr. Faisal Ahmed',
    designation: 'Professor',
    department: MentorDepartment.business,
    university: 'IBA, University of Dhaka',
    researchInterests: ['Entrepreneurship', 'SME Finance', 'Behavioral Economics'],
    bio:
        'Serial mentor for early-stage founders and faculty advisor for the '
        'campus entrepreneurship society.',
    email: 'faisal.ahmed@iba-du.edu',
    phone: '+880-2-9666737 Ext. 8110',
    officeRoom: 'IBA 412',
    availableDays: ['Sun', 'Tue', 'Thu'],
    availableTime: '4:00 PM – 6:00 PM',
  ),
  Mentor(
    id: 'bus-002',
    name: 'Dr. Maliha Chowdhury',
    designation: 'Associate Professor',
    department: MentorDepartment.business,
    university: 'Independent University, Bangladesh',
    researchInterests: ['Marketing Analytics', 'Consumer Behavior', 'Brand Strategy'],
    bio:
        'Advises students on quantitative theses and analytics internships. '
        'Frequently hosts guest lectures with industry partners.',
    email: 'maliha.chowdhury@iub.edu.bd',
    phone: '+880-2-8431645 Ext. 230',
    officeRoom: 'ACB 305',
    availableDays: ['Mon', 'Wed', 'Fri'],
    availableTime: '11:00 AM – 1:00 PM',
  ),

  // ── Mechanical ─────────────────────────────────────────────────────────
  Mentor(
    id: 'me-001',
    name: 'Dr. Tanvir Alam',
    designation: 'Professor',
    department: MentorDepartment.mechanical,
    university: 'BUET',
    researchInterests: ['Robotics', 'Mechatronics', 'Manufacturing Automation'],
    bio:
        'Principal investigator of the Robotics and Automation Lab. '
        'Open to mentoring teams competing in international robotics olympiads.',
    email: 'tanvir.alam@me.buet.ac.bd',
    phone: '+880-2-9665650 Ext. 7615',
    officeRoom: 'ME 511',
    availableDays: ['Sun', 'Tue'],
    availableTime: '2:00 PM – 4:00 PM',
  ),
  Mentor(
    id: 'me-002',
    name: 'Dr. Rubina Yeasmin',
    designation: 'Assistant Professor',
    department: MentorDepartment.mechanical,
    university: 'Khulna University of Engineering & Technology',
    researchInterests: ['Thermal Engineering', 'Energy Efficiency', 'HVAC'],
    bio:
        'Works on energy-efficient HVAC for tropical climates and '
        'mentors capstone teams on building-simulation projects.',
    email: 'rubina.yeasmin@kuet.ac.bd',
    phone: '+880-41-769468 Ext. 410',
    officeRoom: 'ME 207',
    availableDays: ['Mon', 'Thu'],
    availableTime: '10:00 AM – 12:00 PM',
  ),

  // ── Civil ───────────────────────────────────────────────────────────────
  Mentor(
    id: 'ce-001',
    name: 'Dr. Kamrul Hasan',
    designation: 'Professor',
    department: MentorDepartment.civil,
    university: 'BUET',
    researchInterests: ['Structural Engineering', 'Earthquake Resilience', 'Concrete'],
    bio:
        'Specialist in seismic design and retrofitting. Consults for the '
        'national building code review committee.',
    email: 'kamrul.hasan@ce.buet.ac.bd',
    phone: '+880-2-9665650 Ext. 7802',
    officeRoom: 'CE 614',
    availableDays: ['Sun', 'Wed'],
    availableTime: '3:00 PM – 5:00 PM',
  ),
  Mentor(
    id: 'ce-002',
    name: 'Dr. Sumaiya Rahman',
    designation: 'Associate Professor',
    department: MentorDepartment.civil,
    university: 'Chittagong University of Engineering & Technology',
    researchInterests: ['Transportation Engineering', 'Urban Planning', 'GIS'],
    bio:
        'Studies sustainable urban mobility for coastal cities. '
        'Welcomes students interested in data-driven planning.',
    email: 'sumaiya.rahman@cuet.ac.bd',
    phone: '+880-31-714946 Ext. 305',
    officeRoom: 'CE 220',
    availableDays: ['Tue', 'Fri'],
    availableTime: '11:00 AM – 1:00 PM',
  ),

  // ── Others (Mathematics, Physics, Biology, Architecture) ────────────────
  Mentor(
    id: 'oth-001',
    name: 'Dr. Asif Mahmud',
    designation: 'Professor',
    department: MentorDepartment.others,
    university: 'University of Dhaka',
    researchInterests: ['Applied Mathematics', 'Numerical Analysis', 'Mathematical Modeling'],
    bio:
        'Builds numerical models for epidemiology and climate studies. '
        'Mentors a small cohort of students on mathematical computing.',
    email: 'asif.mahmud@du.ac.bd',
    phone: '+880-2-9661900 Ext. 4156',
    officeRoom: 'Math 312',
    availableDays: ['Sun', 'Thu'],
    availableTime: '1:00 PM – 3:00 PM',
  ),
  Mentor(
    id: 'oth-002',
    name: 'Dr. Nusrat Jahan',
    designation: 'Associate Professor',
    department: MentorDepartment.others,
    university: 'Jahangirnagar University',
    researchInterests: ['Molecular Biology', 'Genetics', 'Biotechnology'],
    bio:
        'Studies plant genetics for stress tolerance. '
        'Hosts undergraduate researchers in her wet-lab each semester.',
    email: 'nusrat.jahan@juniv.edu',
    phone: '+880-2-7791045 Ext. 220',
    officeRoom: 'BioSciences 410',
    availableDays: ['Mon', 'Wed'],
    availableTime: '10:00 AM – 12:00 PM',
  ),
];
