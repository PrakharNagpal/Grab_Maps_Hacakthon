# ⚖️ Equal Miles

> **Stop arguing about where to meet. Start being fair about it.**

Equal Miles finds the meeting spot that nobody can complain about — because it's backed by real road travel times, not a finger-in-the-air midpoint.

<br/>

![Equal Miles Banner](flutter_01.png)

<br/>

## The Problem With "Just Meet in the Middle"

Your friend group is scattered across the city. Someone suggests "let's just meet at the midpoint." Sounds fair — but roads aren't straight lines. That "midpoint" café ends up being a 5-minute walk for two people and a 40-minute drive for the third.

**Equal Miles fixes this.** It calls the Grab Directions API for every friend → every venue, measures the actual travel time spread, and ranks venues by who gets the fairest deal.

```
Fairness Gap = longest trip − shortest trip

The closer to zero, the fairer the meetup.
```

<br/>

## ✨ What Makes It Different

| Feature | What it does |
|---|---|
| ⚖️ **Fairness Ranking** | Ranks venues by the gap between the fastest and slowest trip in your group |
| 🏆 **Fairest / Fastest / Closest badges** | Every result tells you which dimension it wins on |
| 📍 **Geographic Center Comparison** | Shows exactly how many minutes fairer the winning venue is vs the naive midpoint |
| 🎯 **Compare Categories** | One click ranks Restaurant, Cafe, Bar, Hawker, Mall — which vibe is fairest *right now* for your group? |
| 🗺️ **Click-to-Place Friends** | Tap anywhere on a live GrabMaps map to drop a friend pin |
| 🔍 **Place Search** | Search friends' locations by address or landmark name |
| 🚗 **5 Travel Modes** | Driving · Motorcycle · Tricycle · Cycling · Walking (auto-caps search radius to 4 km) |
| ⭐ **Recommended But Far** | When your radius is too tight, surfaces 9 curated Singapore landmarks as stretch picks |
| 📡 **Live Address Resolution** | Reverse-geocodes every dropped pin to show a real address |

<br/>

## 🧮 How the Score is Calculated

For each candidate venue, the server concurrently calls the Grab Directions API from **every friend** to that venue, then computes:

```
blended_score =
    unfairness_gap                        (primary — the spread)
  + max_trip          × 0.22             (penalise the worst case)
  + average_trip      × 0.08             (penalise overall effort)
  + centroid_distance × 1/42             (driving proximity tie-breaker)
```

The venue with the **lowest blended score** wins. Ties are broken by unfairness gap → worst trip → centroid distance → total trip time.

> Walking mode uses a stricter `1/18` distance weight and caps the search radius at 4 km automatically.

<br/>

## 🏗️ Architecture

```
Browser
├── Flutter Web (left panel UI)
│   └── dart:js_interop bridge
└── MapLibre GL JS + Grab Maps Style (live map)
         │
         │ HTTP (Dio)
         ▼
Dart / Shelf Backend  ──────────────►  Grab Maps API
(Render.com, Docker)                   - Places nearby
  ├── MeetupService                    - Keyword search
  │   ├── rankMeetup()                 - Reverse geocode
  │   ├── _scorePoint()                - Directions (polyline6)
  │   └── _compareScore()
  └── GrabMapsClient
      └── in-memory response cache
```

<br/>

## 🚀 Getting Started

### Prerequisites

- Flutter 3.x (stable channel)
- Dart SDK (included with Flutter)
- A Grab Maps **Browser API Key** (`GRAB_MAPS_BROWSER_KEY`)
- A Grab Maps **Server API Key** (`GRAB_MAPS_API_KEY`) for the backend

### Run Locally

**1. Start the backend**

```bash
cd server
GRAB_MAPS_API_KEY=your_server_key dart run bin/server.dart
# Listening on http://0.0.0.0:8080
```

**2. Run the Flutter web app**

```bash
flutter pub get
flutter run -d chrome \
  --dart-define=GRAB_MAPS_BROWSER_KEY=your_browser_key \
  --dart-define=FRIENDSHIP_RADIUS_API_BASE_URL=http://localhost:8080
```

<br/>

## ☁️ Deployment

### Frontend → GitHub Pages

Push to `main` and the GitHub Actions workflow handles the rest:

```yaml
# .github/workflows/deploy.yml
flutter build web --release \
  --base-href /Grab_Maps_Hacakthon/ \
  --dart-define=GRAB_MAPS_BROWSER_KEY=${{ secrets.GRAB_MAPS_BROWSER_KEY }}
```

Set `GRAB_MAPS_BROWSER_KEY` in **Repository → Settings → Secrets**.

### Backend → Render.com (Docker)

The server compiles to a self-contained native binary — no Dart runtime needed at runtime:

```dockerfile
FROM dart:stable AS build
RUN dart compile exe bin/server.dart -o bin/server_exe

FROM debian:bookworm-slim
COPY --from=build /app/bin/server_exe /app/server
CMD ["/app/server"]
```

Set `GRAB_MAPS_API_KEY` as an environment variable in the Render dashboard.

<br/>

## 📁 Project Structure

```
grab_maps/
├── lib/
│   ├── main.dart                      UI, state management, scoring display
│   ├── map_bridge.dart                dart:js_interop bindings to MapLibre JS
│   ├── friendship_radius_api.dart     Dio client for the backend
│   └── polyline_codec.dart            Polyline6 decoder with axis-order auto-detection
├── web/
│   └── index.html                     MapLibre setup, click overlay, JS bridge functions
├── server/
│   ├── bin/server.dart                Entry point
│   ├── lib/src/
│   │   ├── server.dart                Shelf router + CORS + error handling
│   │   ├── meetup_service.dart        Ranking engine (the core algorithm)
│   │   └── grab_maps_client.dart      Grab API HTTP client + in-memory cache
│   └── Dockerfile
└── .github/workflows/
    └── deploy.yml                     CI/CD → GitHub Pages
```

<br/>

## 🛣️ What's Next

- [ ] Enable route line visualisation on the map (already coded — flip `_showRouteLines`)
- [ ] Shareable result URLs (encode group state into query params)
- [ ] Additional ranking modes: Pure Fairness / Nobody Suffers / Fastest Total
- [ ] Time-of-day routing (Friday 7 PM traffic awareness)
- [ ] Friend name labels instead of A/B/C
- [ ] Ride cost fairness using Grab fare estimates
- [ ] Public transit mode
- [ ] Real-time multi-user collaboration via WebSockets

<br/>

## 🧰 Tech Stack

`Flutter Web` · `Dart/Shelf` · `MapLibre GL JS 3.6.2` · `Grab Maps SDK` · `Dio` · `Docker` · `Render.com` · `GitHub Pages` · `GitHub Actions`

<br/>

---

Built with ❤️ for the **Grab Maps Hackathon 2026** by [Prakhar Nagpal](https://github.com/PrakharNagpal)

**Live demo →** https://prakharnagpal.github.io/Grab_Maps_Hacakthon/
