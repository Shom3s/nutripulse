# NutriPulse

<p align="center">
  <img src="docs/screenshots/welcome-screen.jpg" width="230" alt="NutriPulse welcome screen">
</p>

<p align="center">
  <b>Smart Health Monitoring and Nutrition Advisory Mobile Application</b>
</p>

<p align="center">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-Mobile_App-02569B?logo=flutter&logoColor=white">
  <img alt="Firebase" src="https://img.shields.io/badge/Firebase-Backend-FFCA28?logo=firebase&logoColor=black">
  <img alt="TensorFlow Lite" src="https://img.shields.io/badge/TensorFlow_Lite-Food_Recognition-FF6F00?logo=tensorflow&logoColor=white">
  <img alt="Platform" src="https://img.shields.io/badge/Platform-Android-3DDC84?logo=android&logoColor=white">
  <img alt="Project" src="https://img.shields.io/badge/Project-Final_Year_Project-7B61FF">
</p>

NutriPulse is an integrated mobile health application developed with Flutter and Firebase. It combines nutrition tracking, food recognition, physical activity monitoring, hydration records, health reporting, AI-assisted guidance, gamification, community interaction, and prototype IoT health monitoring in one platform.

> Final Year Project by **Shomeswaran A/L Mugunthan**  
> Faculty of Information and Communication Technology  
> Universiti Teknikal Malaysia Melaka (UTeM)

---

## Table of Contents

- [Project Overview](#project-overview)
- [Problem Addressed](#problem-addressed)
- [Core Features](#core-features)
- [Application Screenshots](#application-screenshots)
- [Technology Stack](#technology-stack)
- [System Architecture](#system-architecture)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Firebase Configuration](#firebase-configuration)
- [AI Configuration](#ai-configuration)
- [Machine Learning Assets](#machine-learning-assets)
- [Security and Privacy](#security-and-privacy)
- [Current Limitations](#current-limitations)
- [Future Enhancements](#future-enhancements)
- [Academic Context](#academic-context)
- [Author](#author)
- [Disclaimer](#disclaimer)
- [License](#license)

---

## Project Overview

Many users rely on separate applications for calorie tracking, step counting, hydration reminders, health records, activity summaries, and lifestyle advice. This fragmentation makes it difficult to understand daily progress as one connected health picture.

NutriPulse addresses this issue by presenting food intake, calorie and macronutrient data, water consumption, steps, running activity, health scans, progress charts, rewards, and AI-generated guidance through a unified mobile interface.

The application is designed for personal lifestyle monitoring and academic demonstration. It is **not** a medical diagnosis system and does not replace professional medical consultation.

---

## Problem Addressed

NutriPulse focuses on three main problems:

1. **Fragmented health records** — food, water, steps, calories, reports, and advice are often stored in different applications.
2. **Time-consuming food logging** — users may not know the estimated calories and macronutrients of common meals.
3. **Low engagement and limited guidance** — raw health values are difficult to interpret without visual progress, summaries, motivation, and practical suggestions.

---

# Core Features

## 1. User Onboarding and Personalisation

- Gender, age, height, weight, and target weight setup
- Fitness goal selection such as maintaining or gaining weight
- Weekly workout frequency and dietary preference collection
- Weight-change pace selection
- Personalised calorie and macronutrient target generation
- Account registration and secure login

## 2. Smart Dashboard

- Daily calorie summary
- Weekly calorie trend chart
- Macronutrient progress
- Step count and daily activity goal
- Water intake progress
- Health calendar preview
- Recent meals and quick navigation

## 3. Food Logging and Nutrition

- Camera-based food scanning
- Gallery image selection
- Manual food search and entry
- Barcode entry support
- Local food database
- Daily and weekly calorie history
- Macronutrient breakdown for protein, carbohydrates, fat, sugar, and fibre
- Food recognition result with calorie and nutrient estimation
- Smart food warnings
- Portion estimation using plate size or gram input

## 4. Activity and Running

- Daily step tracking
- Weekly movement goals
- Activity calendar
- Monthly activity summary
- Running mode with route map
- Live distance, pace, and duration tracking
- Completed activity summary and XP reward

## 5. Hydration Monitoring

- Daily water target
- Visual intake progress
- Incremental water logging
- Integration with dashboard and health reports

## 6. Health Monitoring and Reports

- ESP32-connected prototype health scan
- Heart-rate and temperature display
- Live scan graph
- Weekly health trend
- Recent scan history
- Advanced health report generation
- Health score and reference-range indicators

## 7. AI Health Coach

- Context-aware health and nutrition responses
- Personalised interpretation of calories, protein, steps, and goals
- Conversational guidance inside the application
- Chat history and quick suggestions

## 8. Gamification

- Experience points (XP)
- User levels and progress bars
- Daily and activity streaks
- Badges and achievements
- Daily missions and challenges
- Reward pop-ups
- Celebration effects
- Leaderboard support

## 9. Community Features

- Community feed
- Post creation and editing
- Stories and story viewers
- Comments and reactions
- Friend profiles and friend requests
- Private messaging
- Group chat
- Community groups
- User interaction and social engagement

## 10. Community Marketplace

- Community marketplace
- Product listings
- Product detail pages
- Buying and selling features
- Order placement
- Buyer order history
- Seller order management

---

# Application Screenshots

## Welcome, Registration, and Login

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/welcome-screen.jpg" width="230"><br><b>Welcome Screen</b></td>
    <td align="center"><img src="docs/screenshots/register.jpg" width="230"><br><b>Create Account</b></td>
    <td align="center"><img src="docs/screenshots/login.jpg" width="230"><br><b>Login</b></td>
  </tr>
</table>

<details>
<summary><b>View complete onboarding flow</b></summary>

<br>

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/onboarding-gender.jpg" width="190"><br>Gender</td>
    <td align="center"><img src="docs/screenshots/onboarding-workouts.jpg" width="190"><br>Workout Frequency</td>
    <td align="center"><img src="docs/screenshots/onboarding-calorie-tracking.jpg" width="190"><br>Tracking Experience</td>
    <td align="center"><img src="docs/screenshots/onboarding-height-weight.jpg" width="190"><br>Height and Weight</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/onboarding-age.jpg" width="190"><br>Age</td>
    <td align="center"><img src="docs/screenshots/onboarding-goal.jpg" width="190"><br>Goal</td>
    <td align="center"><img src="docs/screenshots/onboarding-target-weight.jpg" width="190"><br>Target Weight</td>
    <td align="center"><img src="docs/screenshots/onboarding-weight-pace.jpg" width="190"><br>Weekly Pace</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/onboarding-challenge.jpg" width="190"><br>Main Challenge</td>
    <td align="center"><img src="docs/screenshots/onboarding-diet.jpg" width="190"><br>Diet Preference</td>
    <td align="center"><img src="docs/screenshots/onboarding-goal-projection.jpg" width="190"><br>Goal Projection</td>
    <td align="center"><img src="docs/screenshots/onboarding-plan-generation.jpg" width="190"><br>Plan Generation</td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/onboarding-plan-ready.jpg" width="190"><br>Plan Ready</td>
    <td align="center"><img src="docs/screenshots/onboarding-daily-targets.jpg" width="190"><br>Daily Targets</td>
  </tr>
</table>

</details>

---

## Dashboard and Daily Progress

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/dashboard-home.jpg" width="235"><br><b>Main Dashboard</b></td>
    <td align="center"><img src="docs/screenshots/dashboard-health-calendar.jpg" width="235"><br><b>Health Calendar and Steps</b></td>
    <td align="center"><img src="docs/screenshots/health-score.jpg" width="235"><br><b>Health Score</b></td>
  </tr>
</table>

The dashboard centralises the user's current calorie intake, weekly calorie chart, activity, hydration, and health progress. It also provides quick access to the food, health, activity, community, and profile modules.

---

## Nutrition Overview and History

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/nutrition-dashboard.jpg" width="220"><br><b>Nutrition Dashboard</b></td>
    <td align="center"><img src="docs/screenshots/nutrition-history.jpg" width="220"><br><b>Nutrition History</b></td>
    <td align="center"><img src="docs/screenshots/food-log-overview.jpg" width="220"><br><b>Food Log Overview</b></td>
    <td align="center"><img src="docs/screenshots/nutrition-breakdown.jpg" width="220"><br><b>Nutrition Breakdown</b></td>
  </tr>
</table>

---

## Food Logging and Recognition

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/food-scan-entry.jpg" width="220"><br><b>Scan Food</b></td>
    <td align="center"><img src="docs/screenshots/food-manual-entry.jpg" width="220"><br><b>Manual Entry</b></td>
    <td align="center"><img src="docs/screenshots/food-database.jpg" width="220"><br><b>Food Database</b></td>
    <td align="center"><img src="docs/screenshots/food-recognition-result.jpg" width="220"><br><b>Recognition Result</b></td>
  </tr>
</table>

The food module supports multiple logging methods so users are not dependent on a single input flow. A scanned image can be classified using the included TensorFlow Lite model, while manual search and portion adjustment provide a fallback when recognition is uncertain.

---

## Smart Food Warning and Portion Estimation

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/smart-food-warning.jpg" width="235"><br><b>Smart Food Warning</b></td>
    <td align="center"><img src="docs/screenshots/portion-estimator-plate.jpg" width="235"><br><b>Plate-Based Portion</b></td>
    <td align="center"><img src="docs/screenshots/portion-estimator-grams.jpg" width="235"><br><b>Gram-Based Portion</b></td>
  </tr>
</table>

---

## Recent Meals, Notifications, and Favourites

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/notifications-and-meals.jpg" width="235"><br><b>Notifications and Meals</b></td>
    <td align="center"><img src="docs/screenshots/weekly-calories-and-favourites.jpg" width="235"><br><b>Weekly Calories and Favourites</b></td>
  </tr>
</table>

---

## Activity and Running

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/run-tracker-home.jpg" width="210"><br><b>Run Tracker</b></td>
    <td align="center"><img src="docs/screenshots/activity-calendar.jpg" width="210"><br><b>Activity Calendar</b></td>
    <td align="center"><img src="docs/screenshots/activity-monthly-summary.jpg" width="210"><br><b>Monthly Summary</b></td>
    <td align="center"><img src="docs/screenshots/activity-summary.jpg" width="210"><br><b>Activity Result</b></td>
  </tr>
</table>

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/run-map-start.jpg" width="235"><br><b>Route Map</b></td>
    <td align="center"><img src="docs/screenshots/run-map-style.jpg" width="235"><br><b>Map Style Selection</b></td>
    <td align="center"><img src="docs/screenshots/run-live-tracking.jpg" width="235"><br><b>Live Run Tracking</b></td>
  </tr>
</table>

---

## IoT Health Scan and Health Reports

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/health-monitor-1.jpg" width="220"><br><b>Smart Health Scan</b></td>
    <td align="center"><img src="docs/screenshots/health-monitor-2.jpg" width="220"><br><b>Live Scan Graph</b></td>
    <td align="center"><img src="docs/screenshots/health-monitor-3.jpg" width="220"><br><b>Weekly Health Trend</b></td>
  </tr>
</table>

<p align="center">
  <img src="docs/screenshots/health-monitor-4.jpg" width="520" alt="Advanced health monitoring report">
</p>

The IoT prototype demonstrates how readings such as heart rate and temperature can be displayed, stored, visualised, and included in a generated health report. These readings are for project demonstration and lifestyle awareness only.

---

## AI Health Coach

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/health-monitor-5.jpg" width="260"><br><b>Context-Aware AI Coach</b></td>
  </tr>
</table>

The chatbot can use selected application context, such as calorie intake, protein intake, steps, and user goals, to provide more relevant lifestyle guidance.

---

# Gamification and Rewards

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/gamification-progress.jpg" width="220"><br><b>Gamification Progress</b></td>
    <td align="center"><img src="docs/screenshots/gamification-missions-achievements.jpg" width="220"><br><b>Missions & Achievements</b></td>
    <td align="center"><img src="docs/screenshots/gamification-mission-reward.jpg" width="220"><br><b>Mission Reward</b></td>
    <td align="center"><img src="docs/screenshots/gamification-leaderboard.jpg" width="220"><br><b>Leaderboard</b></td>
  </tr>
</table>

NutriPulse incorporates a gamification system designed to encourage users to maintain consistent healthy habits. Users earn experience points by completing health-related activities, progress through levels, maintain streaks, complete daily missions, unlock achievements, and compare progress through the leaderboard.

---

# Community and Social Features

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/community-feed.jpg" width="220"><br><b>Community Feed</b></td>
    <td align="center"><img src="docs/screenshots/community-post-detail.jpg" width="220"><br><b>Post Detail</b></td>
    <td align="center"><img src="docs/screenshots/community-notifications.jpg" width="220"><br><b>Notifications</b></td>
    <td align="center"><img src="docs/screenshots/community-friends.jpg" width="220"><br><b>Friends</b></td>
  </tr>
</table>

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/community-groups.jpg" width="220"><br><b>Community Groups</b></td>
    <td align="center"><img src="docs/screenshots/community-group-detail.jpg" width="220"><br><b>Group Detail</b></td>
  </tr>
</table>

NutriPulse provides a social health community where users can share progress, interact with posts, connect with friends, receive community notifications, and participate in groups.

---

# Community Marketplace

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/community-marketplace.jpg" width="220"><br><b>Marketplace</b></td>
    <td align="center"><img src="docs/screenshots/community-marketplace-browse.jpg" width="220"><br><b>Browse Marketplace</b></td>
    <td align="center"><img src="docs/screenshots/community-seller-center.jpg" width="220"><br><b>Seller Center</b></td>
    <td align="center"><img src="docs/screenshots/community-cod-orders.jpg" width="220"><br><b>COD Orders</b></td>
  </tr>
</table>

The integrated community marketplace allows users to browse listings and manage marketplace activities within the NutriPulse ecosystem.

---

## IoT Health Monitoring Prototype

<p align="center">
  <img src="docs/screenshots/iot-health-scan-device.jpg" width="430" alt="NutriPulse ESP32 health monitoring device setup">
  &nbsp;&nbsp;
  <img src="docs/screenshots/iot-health-scan-finger.jpg" width="430" alt="NutriPulse IoT sensor finger testing">
</p>

<p align="center">
  <em>ESP32-based health monitoring prototype and live sensor testing.</em>
</p>

---

# Technology Stack

| Layer | Technology |
|---|---|
| Mobile UI | Flutter, Dart |
| Authentication | Firebase Authentication |
| Cloud database | Cloud Firestore |
| Local storage | SharedPreferences and local application storage |
| Food recognition | TensorFlow Lite |
| Food data | CSV and JSON assets |
| Activity integration | Health Connect / Google Fit through Flutter health services |
| Charts | Flutter chart libraries |
| AI assistant | Groq-powered chatbot service |
| Backend functions | Firebase Cloud Functions / Node.js |
| IoT prototype | ESP32 with health sensors |
| Report output | Flutter PDF generation |

---

# System Architecture

```text
User
  │
  ▼
Flutter Mobile Application
  ├── Authentication and Onboarding
  ├── Dashboard
  ├── Food Recognition and Nutrition
  ├── Activity and Run Tracking
  ├── Hydration Tracking
  ├── Health Monitoring and Reports
  ├── AI Health Coach
  ├── Gamification
  ├── Community and Social
  └── Community Marketplace
  │
  ├── Firebase Authentication
  ├── Cloud Firestore
  ├── Firebase Cloud Functions
  ├── Local Assets / TensorFlow Lite
  ├── Health Connect / Google Fit
  ├── Groq AI Service
  └── ESP32 Sensor Prototype
```

---

# Project Structure

```text
nutripulse/
├── android/
├── assets/
│   ├── data/
│   │   └── food_database.csv
│   ├── images/
│   └── ml/
│       ├── food_labels.json
│       └── food_model.tflite
│
├── docs/
│   └── screenshots/
│       ├── activity-calendar.jpg
│       ├── activity-monthly-summary.jpg
│       ├── activity-summary.jpg
│       ├── community-cod-orders.jpg
│       ├── community-feed.jpg
│       ├── community-friends.jpg
│       ├── community-group-detail.jpg
│       ├── community-groups.jpg
│       ├── community-marketplace-browse.jpg
│       ├── community-marketplace.jpg
│       ├── community-notifications.jpg
│       ├── community-post-detail.jpg
│       ├── community-seller-center.jpg
│       ├── gamification-leaderboard.jpg
│       ├── gamification-mission-reward.jpg
│       ├── gamification-missions-achievements.jpg
│       ├── gamification-progress.jpg
│       ├── dashboard-health-calendar.jpg
│       ├── dashboard-home.jpg
│       ├── food-database.jpg
│       ├── food-log-overview.jpg
│       ├── food-manual-entry.jpg
│       ├── food-recognition-result.jpg
│       ├── food-scan-entry.jpg
│       └── ...
│
├── functions/
│   ├── index.js
│   └── package.json
│
├── lib/
│   ├── config/
│   ├── core/
│   │   ├── constants/
│   │   └── utils/
│   ├── database/
│   ├── models/
│   ├── screens/
│   │   ├── activity/
│   │   ├── auth/
│   │   ├── calendar/
│   │   ├── chat/
│   │   ├── community/
│   │   ├── dashboard/
│   │   ├── food/
│   │   ├── friends/
│   │   ├── groups/
│   │   ├── health/
│   │   ├── leaderboard/
│   │   ├── notifications/
│   │   ├── onboarding/
│   │   ├── profile/
│   │   ├── recommendation/
│   │   └── report/
│   ├── services/
│   ├── theme/
│   ├── widgets/
│   └── main.dart
│
├── test/
├── pubspec.yaml
└── README.md
```

---

# Getting Started

## Prerequisites

Install the following tools:

- Flutter SDK
- Dart SDK
- Android Studio or Visual Studio Code
- Android SDK
- An Android device or emulator
- A Firebase project

Check your setup:

```bash
flutter doctor
```

## Clone the Repository

```bash
git clone https://github.com/Shom3s/nutripulse.git
cd nutripulse
```

## Install Dependencies

```bash
flutter pub get
```

## Run the Application

```bash
flutter run
```

To choose a connected device:

```bash
flutter devices
flutter run -d DEVICE_ID
```

## Build an Android APK

```bash
flutter build apk --release
```

The generated APK is normally located at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

---

# Firebase Configuration

1. Create a Firebase project.
2. Add an Android application using the package name configured in the project.
3. Download `google-services.json`.
4. Place it in:

```text
android/app/google-services.json
```

5. Enable the required Firebase services:
   - Authentication
   - Cloud Firestore
   - Cloud Functions, where used
   - Storage, where used
6. Apply appropriate Firestore security rules before testing with real user data.

---

# AI Configuration

The Groq API key must not be committed to GitHub.

Create:

```text
lib/config/groq_config.dart
```

Example:

```dart
class GroqConfig {
  static const String apiKey = 'YOUR_GROQ_API_KEY';
}
```

Ensure the file remains in `.gitignore`:

```gitignore
lib/config/groq_config.dart
.env
*.env
android/key.properties
*.jks
*.keystore
```

For a production deployment, route AI requests through a secure backend instead of embedding a private API key in the mobile application.

---

# Machine Learning Assets

The food-recognition feature uses a TensorFlow Lite model and label file stored under the project assets.

```text
assets/ml/food_model.tflite
assets/ml/food_labels.json
assets/data/food_database.csv
```

Make sure these paths are registered in `pubspec.yaml`.

Example:

```yaml
flutter:
  assets:
    - assets/ml/food_model.tflite
    - assets/ml/food_labels.json
    - assets/data/food_database.csv
```

---

# Security and Privacy

- Do not commit API keys, passwords, keystores, or private Firebase credentials.
- Restrict Firestore access using authenticated user IDs.
- Keep personal health records separated by user account.
- Validate user input before writing to Firestore.
- Apply access controls to private messages and user content.
- Validate marketplace orders and seller ownership.
- Treat AI advice as general lifestyle guidance rather than medical advice.
- Treat ESP32 sensor readings as prototype measurements rather than clinical data.

---

# Current Limitations

- Food-recognition accuracy depends on the supported food classes, lighting, camera angle, image quality, and food presentation.
- Nutrition values are estimates and may vary according to portion size, ingredients, and preparation method.
- Activity data depends on device permissions and available Health Connect or Google Fit information.
- IoT sensor readings are not clinically validated.
- The AI coach does not provide diagnosis, emergency care, or medication prescriptions.
- Community and marketplace features may require additional production-level moderation and security hardening.
- Gamification rewards are designed primarily to improve engagement and do not represent medical achievements.

---

# Future Enhancements

- Expand the food dataset and Malaysian food classes
- Improve food-recognition accuracy
- Improve portion estimation
- Add stronger personalised recommendations
- Improve offline mode and synchronisation
- Add wearable-device integrations
- Add richer sleep and recovery analytics
- Expand gamification challenges and achievements
- Improve community interaction features
- Add stronger community content moderation
- Improve marketplace security and order management
- Strengthen backend security for AI requests
- Improve accessibility and multilingual support
- Perform broader usability and clinical validation studies

---

# Academic Context

This project was developed as a Final Year Project under the Faculty of Information and Communication Technology, Universiti Teknikal Malaysia Melaka.

It demonstrates:

- Mobile application development
- Firebase cloud integration
- Machine learning inference
- Nutrition and health-data visualisation
- Activity tracking
- IoT sensor integration
- AI-assisted health guidance
- Gamification
- Social and community functionality
- Marketplace functionality
- User authentication and cloud data management

---

# Author

**Shomeswaran A/L Mugunthan**  
Bachelor of Computer Science  
Faculty of Information and Communication Technology  
Universiti Teknikal Malaysia Melaka

---

# Disclaimer

NutriPulse is intended for educational, lifestyle-tracking, and prototype demonstration purposes.

It does not provide medical diagnosis, treatment, emergency support, or professional dietary prescriptions.

Health values, nutrition estimates, AI-generated recommendations, and IoT sensor measurements should not be considered substitutes for professional medical advice.

---

# License

This repository is currently provided for academic and portfolio purposes.

Add a suitable licence before permitting reuse, modification, or redistribution.
