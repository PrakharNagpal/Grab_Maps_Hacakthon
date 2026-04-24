# Friendship Radius

Friendship Radius finds fair meetup points by comparing travel times from each
friend to candidate places around a shared centroid.

## Apps

- Flutter web client lives in this repo root.
- Shelf proxy lives in [server/pubspec.yaml](/Users/prakhar/Desktop/Grab/grab_maps/server/pubspec.yaml:1).

## Run The Proxy

From [server/bin/server.dart](/Users/prakhar/Desktop/Grab/grab_maps/server/bin/server.dart:1):

```bash
cd server
GRAB_MAPS_API_KEY=bm_your_key_here dart pub get
GRAB_MAPS_API_KEY=bm_your_key_here dart run bin/server.dart
```

The server starts on `http://0.0.0.0:8080` by default.

## Proxy Endpoints

- `GET /health`
- `POST /api/reverse-geocode`
- `POST /api/places/nearby`
- `POST /api/places/search`
- `POST /api/routes/direction`
- `POST /api/meetup/rank`

Example request:

```json
{
  "friends": [
    { "id": "A", "lat": 1.2834, "lng": 103.8607 },
    { "id": "B", "lat": 1.3009, "lng": 103.8394 },
    { "id": "C", "lat": 1.3521, "lng": 103.8198 }
  ],
  "keyword": "bar",
  "radiusKm": 2,
  "candidateLimit": 6,
  "profile": "driving"
}
```

## Checkpoint Verification

1. Run the Shelf proxy and open `http://localhost:8080/health`.
2. Run `flutter build web` from the repo root.
3. Once both pass, wire the frontend to call the proxy instead of direct Grab
   endpoints.
