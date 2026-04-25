FROM dart:stable AS build

WORKDIR /app

COPY pubspec.* ./
RUN dart pub get

COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server_exe

FROM debian:bookworm-slim

WORKDIR /app

COPY --from=build /app/bin/server_exe /app/server

ENV PORT=8080
EXPOSE 8080

CMD ["/app/server"]
