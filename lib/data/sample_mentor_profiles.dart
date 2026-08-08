/// Sample paid-mentor profiles used by the Mentor Hub marketplace.
///
/// These seed the UI when no Firestore `mentors_marketplace` collection
/// is reachable (offline / first launch). Each entry covers the full
/// [MentorProfile] shape so the cards render with realistic numbers
/// and ratings.
library;

import '../models/mentor_profile.dart';

/// Ten featured mentors spanning different regions, expertise areas,
/// and price points. Order is significant: `featured: true` entries
/// appear first inside the Mentor Hub grid.
const List<MentorProfile> sampleMentorProfiles = <MentorProfile>[
  MentorProfile(
    id: 'm-001',
    name: 'Dr. Aisha Karim',
    designation: 'Former Rhodes Scholar · PhD, Oxford',
    university: 'University of Oxford',
    country: 'United Kingdom',
    education: [
      'PhD, Public Policy — University of Oxford',
      'MPhil, Economics — University of Cambridge',
      'BSS, Economics — University of Dhaka',
    ],
    expertise: [
      'Fully-Funded Scholarships',
      'SOP Editing',
      'Interview Prep',
      'Oxbridge Applications',
    ],
    yearsExperience: 9,
    languages: ['English', 'Bangla', 'Urdu'],
    bio:
        'Aisha has coached 400+ students into Oxbridge, Ivy League, and '
        'Chevening / Commonwealth scholarships. She runs weekly SOP '
        'workshops and personal branding clinics.',
    whatsapp: '+447700900123',
    email: 'aisha.karim@scholarbird.example',
    hourlyPrice: 75,
    packagePrice: 320,
    currency: 'USD',
    rating: 4.9,
    totalReviews: 184,
    successRate: 92,
    studentsHelped: 412,
    responseTime: 'Usually within 1 hour',
    availability: 'Online · 8 slots / week',
    featured: true,
    verified: true,
    profilePhoto: null,
    testimonials: [
      MentorTestimonial(
        author: 'M. Rahim',
        country: 'Bangladesh',
        quote:
            'My SOP went from a draft to a Chevening-winning essay. The '
            'interview prep alone was worth every dollar.',
      ),
      MentorTestimonial(
        author: 'S. Patel',
        country: 'India',
        quote:
            'She helped me get into two Ivy League programs. Honest, '
            'fast, and extremely well-organised.',
      ),
    ],
  ),
  MentorProfile(
    id: 'm-002',
    name: 'James Whitfield',
    designation: 'Ex-Admissions Officer · Stanford MBA',
    university: 'Stanford Graduate School of Business',
    country: 'United States',
    education: [
      'MBA, Stanford GSB',
      'BA, Political Science — Wesleyan University',
    ],
    expertise: [
      'MBA Admissions',
      'Resume Review',
      'Recommendation Strategy',
      'Scholarship Negotiation',
    ],
    yearsExperience: 11,
    languages: ['English', 'Spanish'],
    bio:
        'Former admissions officer turned full-time coach. Specialises in '
        'helping students craft MBA applications that stand out in '
        'round-one piles.',
    whatsapp: '+14155550122',
    email: 'james.whitfield@scholarbird.example',
    hourlyPrice: 120,
    packagePrice: 480,
    currency: 'USD',
    rating: 4.8,
    totalReviews: 152,
    successRate: 88,
    studentsHelped: 287,
    responseTime: 'Usually within 3 hours',
    availability: 'Online · 6 slots / week',
    featured: true,
    verified: true,
    profilePhoto: null,
    testimonials: [
      MentorTestimonial(
        author: 'A. Singh',
        country: 'India',
        quote:
            'James helped me decode what adcoms actually want. Got into '
            'INSEAD with a scholarship.',
      ),
    ],
  ),
  MentorProfile(
    id: 'm-003',
    name: 'Dr. Lina Okonkwo',
    designation: 'Postdoc, MIT · STEM Mentor',
    university: 'Massachusetts Institute of Technology',
    country: 'United States',
    education: [
      'PhD, Mechanical Engineering — MIT',
      'MSc, Aerospace — Imperial College London',
    ],
    expertise: [
      'PhD Applications',
      'Research Proposal',
      'Fully-Funded STEM',
      'Fulbright / DAAD',
    ],
    yearsExperience: 7,
    languages: ['English', 'French', 'Igbo'],
    bio:
        'Helps STEM students land fully-funded PhDs in the US, UK, and '
        'Germany. Strong focus on research proposals and contacting '
        'potential supervisors.',
    whatsapp: '+16175550199',
    email: 'lina.okonkwo@scholarbird.example',
    hourlyPrice: 65,
    packagePrice: 240,
    currency: 'USD',
    rating: 4.9,
    totalReviews: 96,
    successRate: 90,
    studentsHelped: 168,
    responseTime: 'Usually within 4 hours',
    availability: 'Online · 5 slots / week',
    featured: true,
    verified: true,
    profilePhoto: null,
    testimonials: [
      MentorTestimonial(
        author: 'H. Mensah',
        country: 'Ghana',
        quote:
            'Lina helped me cold-email 12 professors — I got replies '
            'from 9 and offers from 3.',
      ),
    ],
  ),
  MentorProfile(
    id: 'm-004',
    name: 'Yuki Tanaka',
    designation: 'MEXT Scholar · Education Consultant',
    university: 'University of Tokyo',
    country: 'Japan',
    education: [
      'MA, Education — University of Tokyo',
      'BA, Linguistics — Kyoto University',
    ],
    expertise: [
      'MEXT Scholarship',
      'Japan Admissions',
      'JLPT Preparation',
      'Cultural Coaching',
    ],
    yearsExperience: 6,
    languages: ['Japanese', 'English'],
    bio:
        'Specialises in MEXT, JDS, and Asian Development Bank scholars. '
        'Walks students through every form, from the research plan to '
        'the language certificate.',
    whatsapp: '+819012345678',
    email: 'yuki.tanaka@scholarbird.example',
    hourlyPrice: 45,
    packagePrice: 180,
    currency: 'USD',
    rating: 4.7,
    totalReviews: 73,
    successRate: 85,
    studentsHelped: 121,
    responseTime: 'Usually within 6 hours',
    availability: 'Online · 4 slots / week',
    featured: true,
    verified: true,
    profilePhoto: null,
    testimonials: [
      MentorTestimonial(
        author: 'R. Pham',
        country: 'Vietnam',
        quote: 'Yuki made the MEXT process feel manageable. I got it!',
      ),
    ],
  ),
  MentorProfile(
    id: 'm-005',
    name: 'Dr. Omar Haddad',
    designation: 'DAAD Alumnus · Engineering Mentor',
    university: 'TU Munich',
    country: 'Germany',
    education: [
      'PhD, Electrical Engineering — TU Munich',
      'MSc, RWTH Aachen',
    ],
    expertise: [
      'DAAD Scholarships',
      'Germany Admissions',
      'Block Account / Visa',
      'STEM Applications',
    ],
    yearsExperience: 8,
    languages: ['Arabic', 'English', 'German'],
    bio:
        'Walks students through the entire Germany journey — from '
        'finding English-taught programs to opening a blocked account '
        'and getting the visa stamp.',
    whatsapp: '+4915123456789',
    email: 'omar.haddad@scholarbird.example',
    hourlyPrice: 55,
    packagePrice: 210,
    currency: 'USD',
    rating: 4.8,
    totalReviews: 118,
    successRate: 89,
    studentsHelped: 203,
    responseTime: 'Usually within 3 hours',
    availability: 'Online · 7 slots / week',
    featured: true,
    verified: true,
    profilePhoto: null,
    testimonials: [
      MentorTestimonial(
        author: 'K. Al-Sayed',
        country: 'Egypt',
        quote:
            'Omar knows every detail of the DAAD process. Saved me weeks '
            'of trial and error.',
      ),
    ],
  ),
  MentorProfile(
    id: 'm-006',
    name: 'Sophie Laurent',
    designation: 'École Normale Supérieure · PhD Candidate',
    university: 'ENS Paris',
    country: 'France',
    education: [
      'PhD Candidate, Mathematics — ENS Paris',
      'MSc, École Polytechnique',
    ],
    expertise: [
      'Eiffel Scholarship',
      'France Admissions',
      'Ecoles Doctoral',
      'Research Statements',
    ],
    yearsExperience: 5,
    languages: ['French', 'English', 'Italian'],
    bio:
        'Helps students crack the French Grandes Écoles and Eiffel '
        'scholarship applications. Strong on research statements and '
        'host-lab outreach.',
    whatsapp: '+33612345678',
    email: 'sophie.laurent@scholarbird.example',
    hourlyPrice: 60,
    packagePrice: 220,
    currency: 'USD',
    rating: 4.7,
    totalReviews: 58,
    successRate: 84,
    studentsHelped: 96,
    responseTime: 'Usually within 5 hours',
    availability: 'Online · 3 slots / week',
    featured: true,
    verified: true,
    profilePhoto: null,
    testimonials: [
      MentorTestimonial(
        author: 'L. Bianchi',
        country: 'Italy',
        quote:
            'Sophie turned my research statement into a story. Got the '
            'Eiffel!',
      ),
    ],
  ),
  MentorProfile(
    id: 'm-007',
    name: 'Daniel Okafor',
    designation: 'MasterCard Foundation Alumnus',
    university: 'University of Cape Town',
    country: 'South Africa',
    education: [
      'MSc, Development Studies — University of Cape Town',
      'BSc, Economics — University of Lagos',
    ],
    expertise: [
      'MasterCard Foundation',
      'African Scholarships',
      'Leadership Essays',
      'Personal Statement',
    ],
    yearsExperience: 6,
    languages: ['English', 'Yoruba'],
    bio:
        'Helps African students win MasterCard Foundation, AAUW, and '
        'African Leadership University scholarships. Focused on '
        'leadership and community-impact essays.',
    whatsapp: '+2348012345678',
    email: 'daniel.okafor@scholarbird.example',
    hourlyPrice: 40,
    packagePrice: 150,
    currency: 'USD',
    rating: 4.8,
    totalReviews: 64,
    successRate: 87,
    studentsHelped: 132,
    responseTime: 'Usually within 2 hours',
    availability: 'Online · 5 slots / week',
    featured: true,
    verified: true,
    profilePhoto: null,
    testimonials: [
      MentorTestimonial(
        author: 'T. Adeyemi',
        country: 'Nigeria',
        quote: 'Daniel is the real deal. Got the MasterCard Foundation '
            'scholarship on my first attempt.',
      ),
    ],
  ),
  MentorProfile(
    id: 'm-008',
    name: 'Mei Chen',
    designation: 'Chevening & CSC Mentor',
    university: 'University of Edinburgh',
    country: 'United Kingdom',
    education: [
      'MSc, International Relations — University of Edinburgh',
      'BA, Peking University',
    ],
    expertise: [
      'Chevening',
      'Chinese Government Scholarship',
      'Leadership Essays',
      'Networking Essays',
    ],
    yearsExperience: 7,
    languages: ['Mandarin', 'English'],
    bio:
        'Specialist in Chevening and CSC applications. Walks students '
        'through leadership essays, networking plans, and interview '
        'rounds.',
    whatsapp: '+447700900456',
    email: 'mei.chen@scholarbird.example',
    hourlyPrice: 50,
    packagePrice: 200,
    currency: 'USD',
    rating: 4.9,
    totalReviews: 142,
    successRate: 91,
    studentsHelped: 245,
    responseTime: 'Usually within 2 hours',
    availability: 'Online · 6 slots / week',
    featured: true,
    verified: true,
    profilePhoto: null,
    testimonials: [
      MentorTestimonial(
        author: 'J. Wang',
        country: 'China',
        quote:
            'Mei decoded the Chevening rubric for me. Got the '
            'scholarship and met the UK Foreign Secretary!',
      ),
    ],
  ),
  MentorProfile(
    id: 'm-009',
    name: 'Dr. Carlos Mendoza',
    designation: 'Fulbright Alumnus · Public Health Mentor',
    university: 'Johns Hopkins University',
    country: 'United States',
    education: [
      'PhD, Public Health — Johns Hopkins',
      'MD, Universidad Nacional Mayor de San Marcos',
    ],
    expertise: [
      'Fulbright',
      'Public Health Programs',
      'Research Proposals',
      'Latin America Scholarships',
    ],
    yearsExperience: 10,
    languages: ['Spanish', 'English', 'Portuguese'],
    bio:
        'Helps Latin American students win Fulbright and other fully-'
        'funded scholarships in public health and medicine.',
    whatsapp: '+14155557788',
    email: 'carlos.mendoza@scholarbird.example',
    hourlyPrice: 70,
    packagePrice: 280,
    currency: 'USD',
    rating: 4.8,
    totalReviews: 87,
    successRate: 86,
    studentsHelped: 154,
    responseTime: 'Usually within 4 hours',
    availability: 'Online · 4 slots / week',
    featured: true,
    verified: true,
    profilePhoto: null,
    testimonials: [
      MentorTestimonial(
        author: 'P. Garcia',
        country: 'Peru',
        quote: 'Carlos made the Fulbright interview feel like a '
            'conversation. Got the award!',
      ),
    ],
  ),
  MentorProfile(
    id: 'm-010',
    name: 'Priya Iyer',
    designation: 'Ivy League Mentor · Ex-Commonwealth Scholar',
    university: 'Harvard University',
    country: 'United States',
    education: [
      'MA, Public Administration — Harvard Kennedy School',
      'BA, Economics — University of Delhi',
    ],
    expertise: [
      'Ivy League Admissions',
      'Commonwealth Scholarships',
      'Personal Branding',
      'Networking',
    ],
    yearsExperience: 8,
    languages: ['English', 'Hindi', 'Tamil'],
    bio:
        'Helps South-Asian students break into Ivy League and '
        'Commonwealth programs. Strong on personal branding and '
        'networking essays.',
    whatsapp: '+16175550987',
    email: 'priya.iyer@scholarbird.example',
    hourlyPrice: 80,
    packagePrice: 340,
    currency: 'USD',
    rating: 4.9,
    totalReviews: 165,
    successRate: 90,
    studentsHelped: 298,
    responseTime: 'Usually within 2 hours',
    availability: 'Online · 5 slots / week',
    featured: true,
    verified: true,
    profilePhoto: null,
    testimonials: [
      MentorTestimonial(
        author: 'A. Sharma',
        country: 'India',
        quote:
            'Priya\'s networking essay framework alone is worth the '
            'investment. Got into Harvard Kennedy School.',
      ),
    ],
  ),
];